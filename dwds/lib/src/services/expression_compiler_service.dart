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

/// Service that handles expression compilation requests.
///
/// Expression compiler service spawns a dartdevc in expression compilation
/// mode in an isolate and communicates with the isolate via send/receive
/// ports. It also handles full dill file read requests from the isolate
/// and redirects them to the asset server.
class ExpressionCompilerService implements ExpressionCompiler {
  static final _logger = Logger('ExpressionCompilerService');
  Isolate _worker;
  final StreamQueue<Object> _responseQueue;
  final ReceivePort _receivePort;
  final SendPort _sendPort;
  final Handler _assetHandler;

  ExpressionCompilerService._(this._worker, this._responseQueue,
      this._receivePort, this._sendPort, this._assetHandler);

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
  /// Performs handshake with the isolate running expression compiler
  /// worker to estabish communication via send/receive ports, returns
  /// the service after the communication is established.
  ///
  /// Users need to stop the service by calling [stop].
  static Future<ExpressionCompilerService> startWithPlatform(
    String address,
    int port,
    Handler assetHandler,
    String workerPath,
    String sdkSummaryPath,
    String librariesPath,
    bool verbose,
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

    var service = ExpressionCompilerService._(
        isolate, responseQueue, receivePort, sendPort, assetHandler);

    return service;
  }

  /// Starts expression compilation service.
  ///
  /// Starts expression compiler worker in an isolate and creates the
  /// expression compilation service that communicates to the worker.
  ///
  /// Uses [address] and [port] to communicate and [assetHandler] to
  /// redirect asset requests to the asset server.
  ///
  /// Uses current SDK to find platform, expression compiler worker,
  /// and libraries definitions.
  ///
  /// Performs handshake with the isolate running expression compiler
  /// worker to estabish communication via send/receive ports, returns
  /// the service after the communication is established.
  ///
  /// Users need to stop the service by calling [stop].
  static Future<ExpressionCompilerService> start(
      String address, int port, Handler assetHandler, bool verbose) {
    final executable = Platform.resolvedExecutable;
    final binDir = p.dirname(executable);
    final sdkDir = p.dirname(binDir);
    final sdkRoot = p.join(sdkDir, 'lib', '_internal');

    var workerPath = p.join(binDir, 'snapshots', 'dartdevc.dart.snapshot');
    var sdkSummaryPath = p.join(sdkRoot, 'ddc_sdk.dill');
    var librariesPath = p.join(sdkDir, 'lib', 'libraries.json');

    return ExpressionCompilerService.startWithPlatform(address, port,
        assetHandler, workerPath, sdkSummaryPath, librariesPath, verbose);
  }

  @override
  Future<bool> updateDependencies(Map<String, String> modules) async {
    if (_worker == null) {
      throw StateError('Expression compilation service has stopped');
    }

    _logger.info('Updating dependencies...');
    _logger.finest('Dependencies: $modules');

    var response = await _send({
      'command': 'UpdateDeps',
      'inputs': [
        for (var moduleName in modules.keys)
          {'path': modules[moduleName], 'moduleName': moduleName},
      ]
    });
    var result = response == null ? false : response['succeeded'] as bool;
    if (result) {
      _logger.info('Updated dependencies.');
    } else {
      var e = response['exception'];
      var s = response['stackTrace'];
      _logger.info('Failed to update dependencies: $e:$s');
    }
    return result;
  }

  @override
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
    _worker = null;
    _logger.info('Stopped.');
  }
}
