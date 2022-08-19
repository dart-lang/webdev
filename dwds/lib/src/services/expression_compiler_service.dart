// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';
import 'package:logging/logging.dart';

import '../utilities/sdk_configuration.dart';
import 'expression_compiler.dart';

class _Compiler {
  static final _logger = Logger('ExpressionCompilerService');
  final StreamQueue<dynamic> _responseQueue;
  final ReceivePort _receivePort;
  final SendPort _sendPort;

  Future<void>? _dependencyUpdate;

  _Compiler._(
    this._responseQueue,
    this._receivePort,
    this._sendPort,
  );

  /// Sends [request] on [_sendPort] and returns the next event from the
  /// response stream.
  Future<Map<String, dynamic>> _send(Map<String, Object> request) async {
    _sendPort.send(request);
    if (!await _responseQueue.hasNext) {
      return {
        'succeeded': false,
        'errors': ['compilation worker response stream closed'],
      };
    }
    final response = await _responseQueue.next;
    if (response is! Map<String, dynamic>) {
      return {
        'succeeded': false,
        'errors': ['compilation worker returned invalid response: $response'],
      };
    }
    return response;
  }

  /// Starts expression compilation service.
  ///
  /// Starts expression compiler worker in an isolate and creates the
  /// expression compilation service that communicates to the worker.
  ///
  /// [sdkConfiguration] describes the locations of SDK files used in
  /// expression compilation (summaries, libraries spec, compiler worker
  /// snapshot).
  ///
  /// [soundNullSafety] indicates if the compiler should support sound
  /// null safety.
  ///
  /// Performs handshake with the isolate running expression compiler
  /// worker to establish communication via send/receive ports, returns
  /// the service after the communication is established.
  ///
  /// Users need to stop the service by calling [stop].
  static Future<_Compiler> start(
    String address,
    int port,
    String moduleFormat,
    bool soundNullSafety,
    SdkConfiguration sdkConfiguration,
    bool verbose,
  ) async {
    sdkConfiguration.validate();

    final librariesUri = sdkConfiguration.librariesUri!;
    final workerUri = sdkConfiguration.compilerWorkerUri!;
    final sdkSummaryUri = soundNullSafety
        ? sdkConfiguration.soundSdkSummaryUri!
        : sdkConfiguration.unsoundSdkSummaryUri!;

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
      '--module-format',
      moduleFormat,
      if (verbose) '--verbose',
      soundNullSafety ? '--sound-null-safety' : '--no-sound-null-safety',
    ];

    _logger.info('Starting...');
    _logger.finest('$workerUri ${args.join(' ')}');

    final receivePort = ReceivePort();
    await Isolate.spawnUri(
      workerUri,
      args,
      receivePort.sendPort,
      // Note(annagrin): ddc snapshot is generated with no asserts, so we have
      // to run it unchecked in case the calling isolate is checked, as it
      // happens, for example, when debugging webdev in VSCode or running tests
      // using 'dart run'
      checked: false,
    );

    final responseQueue = StreamQueue(receivePort);
    final sendPort = await responseQueue.next as SendPort;

    final service = _Compiler._(responseQueue, receivePort, sendPort);

    return service;
  }

  Future<bool> updateDependencies(Map<String, ModuleInfo> modules) async {
    final updateCompleter = Completer();
    _dependencyUpdate = updateCompleter.future;

    _logger.info('Updating dependencies...');
    _logger.finest('Dependencies: $modules');

    final response = await _send({
      'command': 'UpdateDeps',
      'inputs': [
        for (var moduleName in modules.keys)
          {
            'path': modules[moduleName]!.fullDillPath,
            'summaryPath': modules[moduleName]!.summaryPath,
            'moduleName': moduleName
          },
      ]
    });
    final result = (response['succeeded'] as bool?) ?? false;
    if (result) {
      _logger.info('Updated dependencies.');
    } else {
      final errors = response['errors'];
      final exception = response['exception'];
      final s = response['stackTrace'] as String?;
      final stackTrace = s == null ? null : StackTrace.fromString(s);
      _logger.severe(
          'Failed to update dependencies: $errors', exception, stackTrace);
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
    _logger.finest('Waiting for dependencies to update');
    if (_dependencyUpdate == null) {
      _logger
          .warning('Dependencies are not updated before compiling expressions');
      return ExpressionCompilationResult('<compiler is not ready>', true);
    }

    await _dependencyUpdate;

    _logger.finest('Compiling "$expression" at $libraryUri:$line');

    final response = await _send({
      'command': 'CompileExpression',
      'expression': expression,
      'line': line,
      'column': column,
      'jsModules': jsModules,
      'jsScope': jsFrameValues,
      'libraryUri': libraryUri,
      'moduleName': moduleName,
    });

    final errors = response['errors'] as List<String>?;
    final e = response['exception'];
    final s = response['stackTrace'];
    final error = (errors != null && errors.isNotEmpty)
        ? errors.first
        : (e != null ? '$e:$s' : '<unknown error>');
    final procedure = (response['compiledProcedure'] as String?) ?? '';
    final succeeded = (response['succeeded'] as bool?) ?? false;
    final result = succeeded ? procedure : error;

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
/// Uses [_address] and [_port] to communicate and to redirect asset
/// requests to the asset server.
///
/// Configuration created by [_sdkConfigurationProvider] describes the
/// locations of SDK files used in expression compilation (summaries,
/// libraries spec, compiler worker snapshot).
///
/// Users need to stop the service by calling [stop].
class ExpressionCompilerService implements ExpressionCompiler {
  final _compiler = Completer<_Compiler>();
  final String _address;
  final FutureOr<int> _port;
  final bool _verbose;

  final SdkConfigurationProvider _sdkConfigurationProvider;

  ExpressionCompilerService(this._address, this._port,
      {bool verbose = false,
      SdkConfigurationProvider? sdkConfigurationProvider})
      : _verbose = verbose,
        _sdkConfigurationProvider =
            sdkConfigurationProvider ?? DefaultSdkConfigurationProvider();

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
  Future<void> initialize(
      {required String moduleFormat, bool soundNullSafety = false}) async {
    if (_compiler.isCompleted) return;

    final compiler = await _Compiler.start(
      _address,
      await _port,
      moduleFormat,
      soundNullSafety,
      await _sdkConfigurationProvider.configuration,
      _verbose,
    );

    _compiler.complete(compiler);
  }

  @override
  Future<bool> updateDependencies(Map<String, ModuleInfo> modules) async =>
      (await _compiler.future).updateDependencies(modules);

  Future<void> stop() async {
    if (_compiler.isCompleted) return (await _compiler.future).stop();
  }
}
