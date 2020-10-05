// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:path/path.dart' as p;

import '../utilities/dart_uri.dart';
import 'expression_compiler.dart';

class ExpressionCompilerService implements ExpressionCompiler {
  Isolate _worker;
  final Stream _responseStream;
  final ReceivePort _receivePort;
  final SendPort _sendPort;
  final Handler _assetHandler;
  final String _target;
  final Function(Level, String) _logWriter;
  Completer<dynamic> _requestCompleter;

  ExpressionCompilerService._(
    this._worker,
    this._responseStream,
    this._receivePort,
    this._sendPort,
    this._assetHandler,
    this._target,
    this._logWriter,
  ) {
    _responseStream.listen((response) {
      if (_requestCompleter == null) {
        _logWriter(Level.WARNING,
            'ExpressionCompilerService: unexpected response from isolate $response');
        return;
      }
      _requestCompleter.complete(response);
      _requestCompleter = null;
    });
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

    _logWriter(Level.FINEST,
        'ExpressionCompilerService: request: ${request.requestedUri}');

    if (query != '/getResource' || uri == null) {
      return Response.notFound(uri);
    }

    if (!uri.endsWith('.dart') && !uri.endsWith('.dill')) {
      return Response.notFound(uri);
    }

    var serverPath = uri;
    if (uri.endsWith('.dart')) {
      serverPath = DartUri(uri).serverPath;
      serverPath = '$_target/$serverPath';
    }

    _logWriter(Level.FINEST,
        'ExpressionCompilerService: serverpath for $uri: $serverPath');

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
  /// expression compilation service that communicates to the worker and
  /// provides following API for the client:
  ///
  /// [updateDependencies] - (re)load changed full dill files into the
  /// expression compilation worker.
  ///
  /// [compileExpressionToJs] - compile expression to JavaScript to support
  /// expression evaluation fetures in the debugger.
  ///
  /// [stop] - stop the service.
  ///
  /// Performs handshake with the isolate running expression compiler
  /// worker to estabish communication via send/receive ports, returns
  /// the service after the communication is established.
  static Future<ExpressionCompilerService> start(
    String address,
    int port,
    String target,
    Handler assetHandler,
    Function(Level, String) logWriter,
    bool verbose,
  ) async {
    logWriter ??= (Level level, String message) => {};
    final executable = Platform.resolvedExecutable;
    final binDir = p.dirname(executable);
    final sdkDir = p.dirname(binDir);

    final workerPath = p.join(binDir, 'snapshots', 'dartdevc.dart.snapshot');
    final workerUri = Uri.file(workerPath);
    final sdkRoot = p.join(sdkDir, 'lib', '_internal');
    final sdkSummaryPath = Uri.file(p.join(sdkRoot, 'ddc_sdk.dill'));
    final librariesPath = Uri.file(p.join(sdkRoot, 'lib', 'libraries.json'));

    final args = [
      '--experimental-expression-compiler',
      '--libraries-file',
      '$librariesPath',
      '--dart-sdk-summary',
      '$sdkSummaryPath',
      '--asset-server-address',
      address,
      '--asset-server-port',
      '$port',
      if (verbose) '--verbose',
    ];

    logWriter(Level.INFO, 'Starting expression compilation service...');
    logWriter(Level.FINEST, '$workerUri ${args.join(' ')}');

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

    // Wait to get the sendPort from the isolate
    var stream = receivePort.asBroadcastStream();
    var sendPort = await stream.first as SendPort;

    var service = ExpressionCompilerService._(isolate, stream, receivePort,
        sendPort, assetHandler, target, logWriter);

    return service;
  }

  /// Update full dill files for changed modules.
  ///
  /// [modules]: moduleName -> full dill path
  ///
  /// [updateDependencies] needs to be called after every compilation
  /// to update full dil files for changed modules that are loaded into
  /// the expression compiler worker.
  Future<bool> updateDependencies(Map<String, String> modules) async {
    if (_worker == null) {
      throw StateError('Expression compilation service has stopped');
    }
    _requestCompleter = Completer<dynamic>();

    _logWriter(Level.INFO,
        'Updating dependencies for expression compilation service...');
    _logWriter(Level.FINEST, 'Dependencies: $modules');

    _sendPort.send({
      'command': 'UpdateDeps',
      'inputs': [
        for (var moduleName in modules.keys)
          {'path': modules[moduleName], 'moduleName': moduleName},
      ]
    });

    var event = await _requestCompleter.future;
    var response = event as Map<String, dynamic>;

    var result = response['succeeded'] as bool;
    if (result) {
      _logWriter(
          Level.INFO, 'Updated dependencies for expression compilation.');
    } else {
      _logWriter(Level.INFO,
          'Failed to update dependencies for expression compilation.');
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
    _requestCompleter = Completer<dynamic>();

    _logWriter(
        Level.FINEST,
        'ExpressionCompilerService: compiling '
        '"$expression" at $libraryUri:$line');

    _sendPort.send({
      'command': 'CompileExpression',
      'expression': expression,
      'line': line,
      'column': column,
      'jsModules': jsModules,
      'jsScope': jsFrameValues,
      'libraryUri': libraryUri,
      'moduleName': moduleName,
    });

    var event = await _requestCompleter.future;
    var response = event as Map<String, dynamic>;
    var errors = response['errors'] as List<String>;
    var error =
        (errors == null || errors.isEmpty) ? '<unknown error>' : errors.first;
    var succeeded = response['succeeded'] as bool;
    var procedure = response['compiledProcedure'] as String;
    var result = succeeded ? procedure : error;

    return ExpressionCompilationResult(result, !succeeded);
  }

  /// Stop the service
  ///
  /// Terminates the isolate running expression compiler worker
  /// and marks the service as stopped.
  Future<void> stop() async {
    // TODO: make expression compiler worker terminate on shutdown command
    // https://github.com/dart-lang/sdk/issues/43513)
    _sendPort.send({'command': 'Shutdown'});
    _requestCompleter = null;
    _receivePort.close();
    _worker = null;
    _logWriter(Level.INFO, 'Stopped expression compilation service.');
  }
}
