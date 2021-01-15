// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:async/async.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../utilities/dart_uri.dart';
import 'expression_compiler.dart';

final _logger = Logger('ExpressionCompilerService');

class _Compiler {
  final Isolate _worker;
  final StreamQueue<Object> _responseQueue;
  final ReceivePort _receivePort;
  final SendPort _sendPort;

  Future<void> _dependencyUpdate;

  _Compiler._(
    this._worker,
    this._responseQueue,
    this._receivePort,
    this._sendPort,
  );

  /// Sends [request] on [_sendPort] and returns the next event from the
  /// response stream.
  Future<Map<String, Object>> _send(Map<String, Object> request) async {
    _sendPort.send(request);
    return await _responseQueue.hasNext
        ? await _responseQueue.next as Map<String, Object>
        : {
            'succeeded': false,
            'errors': ['compilation service response stream closed'],
          };
  }

  /// Starts expression compilation service.
  ///
  /// Starts expression compiler worker in an isolate and creates the
  /// expression compilation service that communicates to the worker.
  ///
  /// Uses [address] and [port] to communicate and [assetHandler] to
  /// redirect asset requests to the asset server.
  ///
  /// [workerPath] is the path for the expression compiler worker,
  /// [sdkSummaryPath] is the path to the sdk summary dill file
  /// [librariesPath] is the path to libraries definitions file
  /// libraries.json.
  ///
  /// [soundNullSafety] indiciates if the compioler should support sound null
  /// safety.
  ///
  /// Performs handshake with the isolate running expression compiler
  /// worker to estabish communication via send/receive ports, returns
  /// the service after the communication is established.
  ///
  /// Users need to stop the service by calling [stop].
  static Future<_Compiler> start(
    String address,
    int port,
    Handler assetHandler,
    String workerPath,
    String sdkSummaryPath,
    String librariesPath,
    bool verbose,
    bool soundNullSafety,
  ) async {
    final workerUri = Uri.file(workerPath);
    if (!File(workerPath).existsSync()) {
      _logger.severe('Worker path $workerPath does not exist');
    }

    if (!File(sdkSummaryPath).existsSync()) {
      _logger.severe('SDK summary path $sdkSummaryPath does not exist');
    }

    if (!File(librariesPath).existsSync()) {
      _logger.severe('Libraries path $librariesPath does not exist');
    }

    final sdkSummaryUri = Uri.file(sdkSummaryPath);
    final librariesUri = Uri.file(librariesPath);

    final args = [
      '--experimental-expression-compiler',
      '--libraries-file',
      '$librariesUri',
      '--dart-sdk-summary',
      '$sdkSummaryUri',
      '--asset-server-address',
      address,
      '--asset-server-port',
      '$port',
      if (verbose) '--verbose',
      soundNullSafety ? '--sound-null-safety' : '--no-sound-null-safety',
    ];

    _logger.info('Starting...');
    _logger.finest('$workerUri ${args.join(' ')}');

    final receivePort = ReceivePort();
    final isolate = await Isolate.spawnUri(
      workerUri,
      args,
      receivePort.sendPort,
      // Note(annagrin): ddc snapshot is generated with no asserts, so we have
      // to run it unchecked in case the calling isolate is checked, as it
      // happens, for example, when debugging webdev in VSCode or running tests
      // using 'pub run'
      checked: false,
    );

    var responseQueue = StreamQueue(receivePort);
    var sendPort = await responseQueue.next as SendPort;

    var service = _Compiler._(isolate, responseQueue, receivePort, sendPort);

    return service;
  }

  Future<bool> updateDependencies(Map<String, ModuleInfo> modules) async {
    if (_worker == null) {
      throw StateError('Expression compilation service has stopped');
    }
    var updateCompleter = Completer();
    _dependencyUpdate = updateCompleter.future;

    _logger.info('Updating dependencies...');
    _logger.finest('Dependencies: $modules');

    var response = await _send({
      'command': 'UpdateDeps',
      'inputs': [
        for (var moduleName in modules.keys)
          {
            'path': modules[moduleName].fullDillPath,
            'summaryPath': modules[moduleName].summaryPath,
            'moduleName': moduleName
          },
      ]
    });
    var result = response == null ? false : response['succeeded'] as bool;
    if (result) {
      _logger.info('Updated dependencies.');
    } else {
      var e = response['exception'];
      var s = response['stackTrace'];
      _logger.severe('Failed to update dependencies: $e:$s');
    }
    updateCompleter.complete();
    return result;
  }

  Future<ExpressionCompilationResult> compileExpressionToJs(
    String isolateId,
    String libraryUri,
    int line,
    int column,
    Map<String, String> jsModules,
    Map<String, String> jsFrameValues,
    String moduleName,
    String expression,
  ) async {
    if (_worker == null) {
      throw StateError('Expression compilation service has stopped');
    }

    _logger.finest('Waiting for dependencies to update');
    await _dependencyUpdate;

    _logger.finest('Compiling "$expression" at $libraryUri:$line');

    var response = await _send({
      'command': 'CompileExpression',
      'expression': expression,
      'line': line,
      'column': column,
      'jsModules': jsModules,
      'jsScope': jsFrameValues,
      'libraryUri': libraryUri,
      'moduleName': moduleName,
    });

    var succeeded = false;
    var result = '<unknown error>';

    if (response != null) {
      var errors = response['errors'] as List<String>;
      var e = response['exception'];
      var s = response['stackTrace'];
      var error = (errors != null && errors.isNotEmpty)
          ? errors.first
          : (e != null ? '$e:$s' : '<unknown error>');
      var procedure = response['compiledProcedure'] as String;
      succeeded = response['succeeded'] as bool;
      result = succeeded ? procedure : error;
    }
    if (succeeded) {
      _logger.finest('Compiled "$expression" to: $result');
    } else {
      _logger.finest('Failed to compile "$expression": $result');
    }
    return ExpressionCompilationResult(result, !succeeded);
  }

  /// Stops the service.
  ///
  /// Terminates the isolate running expression compiler worker
  /// and marks the service as stopped.
  Future<void> stop() async {
    _sendPort.send({'command': 'Shutdown'});
    _receivePort.close();
    _logger.info('Stopped.');
  }
}

/// Service that handles expression compilation requests.
///
/// Expression compiler service spawns a dartdevc in expression compilation
/// mode in an isolate and communicates with the isolate via send/receive
/// ports. It also handles full dill file read requests from the isolate
/// and redirects them to the asset server.
///
/// Uses [_address] and [_port] to communicate and [_assetHandler] to
/// redirect asset requests to the asset server.
///
/// [_sdkRoot] is the path to the directory containing the sdk summary files,
/// [_workerPath] is the path to the DDC worker snapshot,
/// [_librariesPath] is the path to libraries definitions file
/// libraries.json.
///
/// Users need to stop the service by calling [stop].
class ExpressionCompilerService implements ExpressionCompiler {
  final _compiler = Completer<_Compiler>();
  final String _address;
  final int _port;
  final Handler _assetHandler;
  final bool _verbose;

  final String _sdkRoot;
  final String _librariesPath;
  final String _workerPath;

  ExpressionCompilerService(
      this._address, this._port, this._assetHandler, this._verbose,
      {String sdkRoot, String librariesPath, String workerPath})
      : _sdkRoot = sdkRoot,
        _librariesPath = librariesPath,
        _workerPath = workerPath;

  @override
  Future<ExpressionCompilationResult> compileExpressionToJs(
          String isolateId,
          String libraryUri,
          int line,
          int column,
          Map<String, String> jsModules,
          Map<String, String> jsFrameValues,
          String moduleName,
          String expression) async =>
      (await _compiler.future).compileExpressionToJs(isolateId, libraryUri,
          line, column, jsModules, jsFrameValues, moduleName, expression);

  @override
  Future<void> initialize({bool soundNullSafety}) async {
    if (_compiler.isCompleted) return;
    soundNullSafety ??= false;

    final executable = Platform.resolvedExecutable;
    final binDir = p.dirname(executable);
    final sdkDir = p.dirname(binDir);

    var sdkRoot = _sdkRoot ?? p.join(sdkDir, 'lib', '_internal');
    var sdkSummaryPath = soundNullSafety
        ? p.join(sdkRoot, 'ddc_outline_sound.dill')
        : p.join(sdkRoot, 'ddc_sdk.dill');
    var librariesPath =
        _librariesPath ?? p.join(sdkDir, 'lib', 'libraries.json');
    var workerPath =
        _workerPath ?? p.join(binDir, 'snapshots', 'dartdevc.dart.snapshot');

    var compiler = await _Compiler.start(_address, _port, _assetHandler,
        workerPath, sdkSummaryPath, librariesPath, _verbose, soundNullSafety);

    _compiler.complete(compiler);
  }

  @override
  Future<bool> updateDependencies(Map<String, ModuleInfo> modules) async =>
      (await _compiler.future).updateDependencies(modules);

  Future<void> stop() async {
    if (_compiler.isCompleted) return (await _compiler.future).stop();
  }

  /// Handles resource requests from expression compiler worker.
  ///
  /// Handles REST get requests of the form:
  /// http://host:port/getResource?uri=<resource uri>
  ///
  /// Where the resource uri can be a package Uri for a dart file
  /// or a server path for a full dill file.
  /// Translates given resource uri to a server path and redirects
  /// the request to the asset handler.
  FutureOr<Response> handler(Request request) {
    var uri = request.requestedUri.queryParameters['uri'];
    var query = request.requestedUri.path;

    _logger.finest('request: ${request.requestedUri}');

    if (query != '/getResource' || uri == null) {
      return Response.notFound(uri);
    }

    if (!uri.endsWith('.dart') && !uri.endsWith('.dill')) {
      return Response.notFound(uri);
    }

    var serverPath = uri;
    if (uri.endsWith('.dart')) {
      serverPath = DartUri(uri).serverPath;
    }

    _logger.finest('serverpath for $uri: $serverPath');

    request = Request(
        'GET',
        Uri(
          scheme: request.requestedUri.scheme,
          host: request.requestedUri.host,
          port: request.requestedUri.port,
          path: serverPath,
        ));

    return _assetHandler(request);
  }
}
