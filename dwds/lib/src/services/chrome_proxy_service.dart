// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/data/debug_event.dart';
import 'package:dwds/data/register_event.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/debugging/location.dart';
import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/debugging/modules.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/debugging/skip_list.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/batched_expression_evaluator.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/services/expression_evaluator.dart';
import 'package:dwds/src/services/proxy_service.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart' hide LogRecord;
import 'package:vm_service/vm_service.dart' hide vmServiceVersion;
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService extends ProxyService {
  /// Signals when isolate starts.
  Future<void> get isStarted => _startedCompleter.future;
  Completer<void> _startedCompleter = Completer<void>();

  /// Signals when expression compiler is ready to evaluate.
  Future<void> get isCompilerInitialized => _compilerCompleter.future;
  Completer<void> _compilerCompleter = Completer<void>();

  /// The root at which we're serving.
  final String root;

  final RemoteDebugger remoteDebugger;
  final ExecutionContext executionContext;

  final AssetReader _assetReader;

  final Locations _locations;

  final SkipLists _skipLists;

  final Modules _modules;

  /// Provides debugger-related functionality.
  Future<Debugger> get debuggerFuture => _debuggerCompleter.future;
  final _debuggerCompleter = Completer<Debugger>();

  /// Provides variable inspection functionality.
  AppInspector get inspector {
    if (_inspector == null) {
      throw StateError('No running isolate (inspector is not set).');
    }
    return _inspector!;
  }

  AppInspector? _inspector;

  /// Determines if there an isolate running currently.
  ///
  /// [_inspector] is `null` iff the isolate is not running,
  /// for example, before the first isolate starts or during
  /// a hot restart.
  bool get _isIsolateRunning => _inspector != null;

  StreamSubscription<ConsoleAPIEvent>? _consoleSubscription;

  /// If non-null, a resume event should await the result of this after resuming
  /// execution.
  ///
  /// This is used to complete a hot reload.
  Future<void> Function()? _finishHotReloadOnResume;

  final _logger = Logger('ChromeProxyService');

  final ExpressionCompiler? _compiler;
  ExpressionEvaluator? _expressionEvaluator;

  bool terminatingIsolates = false;

  ChromeProxyService._(
    super.vm,
    this.root,
    this._assetReader,
    this.remoteDebugger,
    this._modules,
    this._locations,
    this._skipLists,
    this.executionContext,
    this._compiler,
  ) {
    final debugger = Debugger.create(
      remoteDebugger,
      streamNotify,
      _locations,
      _skipLists,
      root,
    );
    debugger.then(_debuggerCompleter.complete);
  }

  static Future<ChromeProxyService> create(
    RemoteDebugger remoteDebugger,
    String root,
    AssetReader assetReader,
    AppConnection appConnection,
    ExecutionContext executionContext,
    ExpressionCompiler? expressionCompiler,
  ) async {
    final vm = VM(
      name: 'ChromeDebugProxy',
      operatingSystem: Platform.operatingSystem,
      startTime: DateTime.now().millisecondsSinceEpoch,
      version: Platform.version,
      isolates: [],
      isolateGroups: [],
      systemIsolates: [],
      systemIsolateGroups: [],
      targetCPU: 'Web',
      hostCPU: 'DWDS',
      architectureBits: -1,
      pid: -1,
    );

    final modules = Modules(root);
    final locations = Locations(assetReader, modules, root);
    final skipLists = SkipLists(root);
    final service = ChromeProxyService._(
      vm,
      root,
      assetReader,
      remoteDebugger,
      modules,
      locations,
      skipLists,
      executionContext,
      expressionCompiler,
    );
    safeUnawaited(service.createIsolate(appConnection, newConnection: true));
    return service;
  }

  /// Reinitializes any caches so that they can be recomputed across hot reload.
  ///
  /// We use the [ModifiedModuleReport] to more efficiently invalidate caches.
  Future<void> _reinitializeForHotReload(
    Map<String, List> reloadedModules,
  ) async {
    final entrypoint = inspector.appConnection.request.entrypointPath;
    final modifiedModuleReport = await globalToolConfiguration.loadStrategy
        .reinitializeProviderAfterHotReload(entrypoint, reloadedModules);
    await _initializeEntrypoint(
      entrypoint,
      modifiedModuleReport: modifiedModuleReport,
    );
    await inspector.initialize(modifiedModuleReport: modifiedModuleReport);
  }

  /// Initializes metadata in [Locations], [Modules], and [ExpressionCompiler].
  ///
  /// If [modifiedModuleReport] is not null, only removes and reinitializes
  /// modified metadata.
  Future<void> _initializeEntrypoint(
    String entrypoint, {
    ModifiedModuleReport? modifiedModuleReport,
  }) async {
    await _modules.initialize(
      entrypoint,
      modifiedModuleReport: modifiedModuleReport,
    );
    await _locations.initialize(
      entrypoint,
      modifiedModuleReport: modifiedModuleReport,
    );
    await _skipLists.initialize(
      entrypoint,
      modifiedModuleReport: modifiedModuleReport,
    );
    // We do not need to wait for compiler dependencies to be updated as the
    // [ExpressionEvaluator] is robust to evaluation requests during updates.
    safeUnawaited(_updateCompilerDependencies(entrypoint));
  }

  Future<void> _updateCompilerDependencies(String entrypoint) async {
    final loadStrategy = globalToolConfiguration.loadStrategy;
    final moduleFormat = loadStrategy.moduleFormat;
    final canaryFeatures = loadStrategy.buildSettings.canaryFeatures;
    final experiments = loadStrategy.buildSettings.experiments;

    _logger.info('Initializing expression compiler for $entrypoint');

    final compilerOptions = CompilerOptions(
      moduleFormat: ModuleFormat.values.byName(moduleFormat),
      canaryFeatures: canaryFeatures,
      experiments: experiments,
    );

    final compiler = _compiler;
    if (compiler != null) {
      await compiler.initialize(compilerOptions);
      final dependencies = await loadStrategy.moduleInfoForEntrypoint(
        entrypoint,
      );
      await captureElapsedTime(() async {
        final result = await compiler.updateDependencies(dependencies);
        // Expression evaluation is ready after dependencies are updated.
        if (!_compilerCompleter.isCompleted) _compilerCompleter.complete();
        return result;
      }, (result) => DwdsEvent.compilerUpdateDependencies(entrypoint));
    }
  }

  Future<void> _prewarmExpressionCompilerCache() async {
    // Exit early if the expression evaluation is not enabled.
    if (_compiler == null || _expressionEvaluator == null) {
      return;
    }
    // Wait until the inspector is ready.
    await isInitialized;

    // Pre-warm the flutter framework module cache in the compiler.
    //
    // Flutter inspector relies on evaluations in widget_inspector
    // library, which is a part of the flutter framework module, to
    // produce widget trees, draw the layout explorer, show hover
    // cards etc.
    // Pre-warming the cache while DevTools is still loading helps
    // Flutter Inspector start faster.
    final libraryToCache = await inspector.flutterWidgetInspectorLibrary;
    if (libraryToCache != null) {
      final isolateId = inspector.isolateRef.id;
      final libraryId = libraryToCache.id;
      if (isolateId != null && libraryId != null) {
        _logger.finest(
          'Caching ${libraryToCache.uri} in expression compiler worker',
        );
        await evaluate(isolateId, libraryId, 'true');
      }
    }
  }

  /// Creates a new isolate.
  ///
  /// Only one isolate at a time is supported, but they should be cleaned up
  /// with [destroyIsolate] and recreated with this method there is a hot
  /// restart or full page refresh.
  ///
  /// If [newConnection] is true, this method does not recompute metadata
  /// information as the metadata couldn't have changed.
  @override
  Future<void> createIsolate(
    AppConnection appConnection, {
    bool newConnection = false,
  }) async {
    // Inspector is null if the previous isolate is destroyed.
    if (_isIsolateRunning) {
      throw UnsupportedError(
        'Cannot create multiple isolates for the same app',
      );
    }
    // Waiting for the debugger to be ready before initializing the entrypoint.
    //
    // Note: moving `await debugger` after the `_initializeEntryPoint` call
    // causes `getcwd` system calls to fail. Since that system call is used
    // in first `Uri.base` call in the expression compiler service isolate,
    // the expression compiler service will fail to start.
    // Issue: https://github.com/dart-lang/webdev/issues/1282
    final debugger = await debuggerFuture;
    final entrypoint = appConnection.request.entrypointPath;
    if (!newConnection) {
      await globalToolConfiguration.loadStrategy.trackEntrypoint(entrypoint);
    }
    await _initializeEntrypoint(entrypoint);

    debugger.notifyPausedAtStart();
    _inspector = await AppInspector.create(
      appConnection,
      remoteDebugger,
      _assetReader,
      _locations,
      root,
      debugger,
      executionContext,
    );

    final compiler = _compiler;
    _expressionEvaluator =
        compiler == null
            ? null
            : BatchedExpressionEvaluator(
              entrypoint,
              inspector,
              debugger,
              _locations,
              _modules,
              compiler,
            );

    safeUnawaited(_prewarmExpressionCompilerCache());

    safeUnawaited(
      appConnection.onStart.then((_) {
        debugger.resumeFromStart();
        _startedCompleter.complete();
      }),
    );

    safeUnawaited(appConnection.onDone.then((_) => destroyIsolate()));

    final isolateRef = inspector.isolateRef;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Listen for `registerExtension` and `postEvent` calls.
    _setUpChromeConsoleListeners(isolateRef);

    vm.isolates?.add(isolateRef);

    streamNotify(
      'Isolate',
      Event(
        kind: EventKind.kIsolateStart,
        timestamp: timestamp,
        isolate: isolateRef,
      ),
    );
    streamNotify(
      'Isolate',
      Event(
        kind: EventKind.kIsolateRunnable,
        timestamp: timestamp,
        isolate: isolateRef,
      ),
    );

    // TODO: We shouldn't need to fire these events since they exist on the
    // isolate, but devtools doesn't recognize extensions after a page refresh
    // otherwise.
    for (final extensionRpc in await inspector.getExtensionRpcs()) {
      streamNotify(
        'Isolate',
        Event(
          kind: EventKind.kServiceExtensionAdded,
          timestamp: timestamp,
          isolate: isolateRef,
        )..extensionRPC = extensionRpc,
      );
    }

    // If the new isolate was created as part of a restart, send a
    // kPausePostRequest event to notify client that the app is paused so that
    // it can resume:
    if (hasPendingRestart) {
      streamNotify(
        'Debug',
        Event(
          kind: EventKind.kPausePostRequest,
          timestamp: timestamp,
          isolate: isolateRef,
        ),
      );
    }

    // The service is considered initialized when the first isolate is created.
    if (!initializedCompleter.isCompleted) initializedCompleter.complete();
  }

  /// Should be called when there is a hot restart or full page refresh.
  ///
  /// Clears out the [_inspector] and all related cached information.
  @override
  void destroyIsolate() {
    _logger.fine('Destroying isolate');
    if (!_isIsolateRunning) return;

    final isolate = inspector.isolate;
    final isolateRef = inspector.isolateRef;

    initializedCompleter = Completer<void>();
    _startedCompleter = Completer<void>();
    _compilerCompleter = Completer<void>();
    streamNotify(
      'Isolate',
      Event(
        kind: EventKind.kIsolateExit,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isolate: isolateRef,
      ),
    );
    vm.isolates?.removeWhere((ref) => ref.id == isolate.id);
    _inspector = null;
    _expressionEvaluator?.close();
    _consoleSubscription?.cancel();
    _consoleSubscription = null;
  }

  /// Removes the breakpoints in the running isolate.
  Future<void> disableBreakpoints() async {
    if (!_isIsolateRunning) return;
    final isolate = inspector.isolate;

    final debugger = await debuggerFuture;
    await Future.wait([
      for (final breakpoint in isolate.breakpoints ?? <Breakpoint>[])
        debugger.removeBreakpoint(breakpoint.id!),
    ]);
  }

  @override
  Future<Breakpoint> addBreakpoint(
    String isolateId,
    String scriptId,
    int line, {
    int? column,
  }) {
    return wrapInErrorHandlerAsync(
      'addBreakpoint',
      () => _addBreakpoint(isolateId, scriptId, line),
    );
  }

  Future<Breakpoint> _addBreakpoint(
    String isolateId,
    String scriptId,
    int line, {
    int? column,
  }) async {
    await isInitialized;
    _checkIsolate('addBreakpoint', isolateId);
    return (await debuggerFuture).addBreakpoint(scriptId, line, column: column);
  }

  @override
  Future<Breakpoint> addBreakpointAtEntry(String isolateId, String functionId) {
    return rpcNotSupportedFuture('addBreakpointAtEntry');
  }

  @override
  Future<Breakpoint> addBreakpointWithScriptUri(
    String isolateId,
    String scriptUri,
    int line, {
    int? column,
  }) => wrapInErrorHandlerAsync(
    'addBreakpointWithScriptUri',
    () =>
        _addBreakpointWithScriptUri(isolateId, scriptUri, line, column: column),
  );

  Future<Breakpoint> _addBreakpointWithScriptUri(
    String isolateId,
    String scriptUri,
    int line, {
    int? column,
  }) async {
    await isInitialized;
    _checkIsolate('addBreakpointWithScriptUri', isolateId);
    if (Uri.parse(scriptUri).scheme == 'dart') {
      // TODO(annagrin): Support setting breakpoints in dart SDK locations.
      // Issue: https://github.com/dart-lang/webdev/issues/1584
      throw RPCError(
        'addBreakpoint',
        102,
        'The VM is unable to add a breakpoint '
            'at the specified line or function: $scriptUri:$line:$column: '
            'breakpoints in dart SDK locations are not supported yet.',
      );
    }
    final dartUri = DartUri(scriptUri, root);
    final scriptRef = await inspector.scriptRefFor(dartUri.serverPath);
    final scriptId = scriptRef?.id;
    if (scriptId == null) {
      throw RPCError(
        'addBreakpoint',
        102,
        'The VM is unable to add a breakpoint '
            'at the specified line or function: $scriptUri:$line:$column: '
            'cannot find script ID for ${dartUri.serverPath}',
      );
    }
    return (await debuggerFuture).addBreakpoint(scriptId, line, column: column);
  }

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map? args,
  }) => wrapInErrorHandlerAsync(
    'callServiceExtension',
    () => _callServiceExtension(method, isolateId: isolateId, args: args),
  );

  Future<Response> _callServiceExtension(
    String method, {
    String? isolateId,
    Map? args,
  }) async {
    await isInitialized;
    isolateId ??= _inspector?.isolate.id;
    _checkIsolate('callServiceExtension', isolateId);
    args ??= <String, String>{};
    final stringArgs = args.map(
      (k, v) => MapEntry(
        k is String ? k : jsonEncode(k),
        v is String ? v : jsonEncode(v),
      ),
    );
    if (!(await inspector.getExtensionRpcs()).contains(method)) {
      throw RPCError(
        method,
        RPCErrorKind.kMethodNotFound.code,
        'Unknown service method: $method',
      );
    }
    final expression = globalToolConfiguration.loadStrategy.dartRuntimeDebugger
        .invokeExtensionJsExpression(method, jsonEncode(stringArgs));
    final result = await inspector.jsEvaluate(expression, awaitPromise: true);
    final decodedResponse =
        jsonDecode(result.value as String) as Map<String, dynamic>;
    if (decodedResponse.containsKey('code') &&
        decodedResponse.containsKey('message') &&
        decodedResponse.containsKey('data')) {
      // ignore: only_throw_errors
      throw RPCError(
        method,
        decodedResponse['code'] as int,
        // ignore: avoid-unnecessary-type-casts
        decodedResponse['message'] as String,
        decodedResponse['data'] as Map,
      );
    } else {
      return Response()..json = decodedResponse;
    }
  }

  Future<Response> _getEvaluationResult(
    String isolateId,
    Future<RemoteObject> Function() evaluation,
    String expression,
  ) async {
    try {
      final result = await evaluation();
      if (!_isIsolateRunning || isolateId != inspector.isolate.id) {
        _logger.fine(
          'Cannot get evaluation result for isolate $isolateId: '
          ' isolate exited.',
        );
        return ErrorRef(
          kind: 'error',
          message: 'Isolate exited',
          id: createId(),
        );
      }

      // Handle compilation errors, internal errors,
      // and reference errors from JavaScript evaluation in chrome.
      if (_hasEvaluationError(result.type)) {
        if (_hasReportableEvaluationError(result.type)) {
          _logger.warning(
            'Failed to evaluate expression \'$expression\': '
            '${result.type}: ${result.value}.',
          );

          _logger.info(
            'Please follow instructions at '
            'https://github.com/dart-lang/webdev/issues/956 '
            'to file a bug.',
          );
        }
        return ErrorRef(
          kind: 'error',
          message: '${result.type}: ${result.value}',
          id: createId(),
        );
      }
      return await _instanceRef(result);
    } on RPCError catch (_) {
      rethrow;
    } catch (e, s) {
      // Handle errors that throw exceptions, such as invalid JavaScript
      // generated by the expression evaluator.
      _logger.warning('Failed to evaluate expression \'$expression\'. ');
      _logger.info(
        'Please follow instructions at '
        'https://github.com/dart-lang/webdev/issues/956 '
        'to file a bug.',
      );
      _logger.info('$e:$s');
      return ErrorRef(kind: 'error', message: '<unknown>', id: createId());
    }
  }

  bool _hasEvaluationError(String type) => type.contains('Error');

  // Decides if the error is serious enough to be shown to the user
  // to encourage bug reporting.
  bool _hasReportableEvaluationError(String type) {
    if (!_hasEvaluationError(type)) return false;

    if (type == EvaluationErrorKind.compilation ||
        type == EvaluationErrorKind.asyncFrame) {
      return false;
    }
    return true;
  }

  @override
  Future<Response> evaluate(
    String isolateId,
    String targetId,
    String expression, {
    Map<String, String>? scope,
    // TODO(798) - respect disableBreakpoints.
    bool? disableBreakpoints,

    /// Note that `idZoneId` arguments will be ignored. This parameter is only
    /// here to make this method is a valid override of
    /// [VmServiceInterface.evaluate].
    String? idZoneId,
  }) => wrapInErrorHandlerAsync(
    'evaluate',
    () => _evaluate(isolateId, targetId, expression, scope: scope),
  );

  Future<Response> _evaluate(
    String isolateId,
    String targetId,
    String expression, {
    Map<String, String>? scope,
  }) {
    // TODO(798) - respect disableBreakpoints.
    return captureElapsedTime(() async {
      await isInitialized;
      final evaluator = _expressionEvaluator;
      if (evaluator != null) {
        await isCompilerInitialized;
        _checkIsolate('evaluate', isolateId);

        late Obj object;
        try {
          object = await inspector.getObject(targetId);
        } catch (_) {
          return ErrorRef(
            kind: 'error',
            message:
                'Evaluate is called on an unsupported target:'
                '$targetId',
            id: createId(),
          );
        }

        final library = object is Library ? object : inspector.isolate.rootLib;

        if (object is Instance) {
          // Evaluate is called on a target - convert this to a dart
          // expression and scope by adding a target variable to the
          // expression and the scope, for example:
          //
          // Library: 'package:hello_world/main.dart'
          // Expression: 'hashCode' => 'x.hashCode'
          // Scope: {} => { 'x' : targetId }

          final target = _newVariableForScope(scope);
          expression = '$target.$expression';
          scope = (scope ?? {})..addAll({target: targetId});
        }

        return await _getEvaluationResult(
          isolateId,
          () => evaluator.evaluateExpression(
            isolateId,
            library?.uri,
            expression,
            scope,
          ),
          expression,
        );
      }
      throw RPCError(
        'evaluate',
        RPCErrorKind.kInvalidRequest.code,
        'Expression evaluation is not supported for this configuration.',
      );
    }, (result) => DwdsEvent.evaluate(expression, result));
  }

  String _newVariableForScope(Map<String, String>? scope) {
    // Find a new variable not in scope.
    var candidate = 'x';
    while (scope?.containsKey(candidate) ?? false) {
      candidate += '\$1';
    }
    return candidate;
  }

  @override
  Future<Response> evaluateInFrame(
    String isolateId,
    int frameIndex,
    String expression, {
    Map<String, String>? scope,
    // TODO(798) - respect disableBreakpoints.
    bool? disableBreakpoints,

    /// Note that `idZoneId` arguments will be ignored. This parameter is only
    /// here to make this method is a valid override of
    /// [VmServiceInterface.evaluateInFrame].
    String? idZoneId,
  }) => wrapInErrorHandlerAsync(
    'evaluateInFrame',
    () => _evaluateInFrame(isolateId, frameIndex, expression, scope: scope),
  );

  Future<Response> _evaluateInFrame(
    String isolateId,
    int frameIndex,
    String expression, {
    Map<String, String>? scope,
  }) {
    // TODO(798) - respect disableBreakpoints.

    return captureElapsedTime(() async {
      await isInitialized;
      final evaluator = _expressionEvaluator;
      if (evaluator != null) {
        await isCompilerInitialized;
        _checkIsolate('evaluateInFrame', isolateId);

        return await _getEvaluationResult(
          isolateId,
          () => evaluator.evaluateExpressionInFrame(
            isolateId,
            frameIndex,
            expression,
            scope,
          ),
          expression,
        );
      }
      throw RPCError(
        'evaluateInFrame',
        RPCErrorKind.kInvalidRequest.code,
        'Expression evaluation is not supported for this configuration.',
      );
    }, (result) => DwdsEvent.evaluateInFrame(expression, result));
  }

  @override
  Future<Isolate> getIsolate(String isolateId) =>
      wrapInErrorHandlerAsync('getIsolate', () => _getIsolate(isolateId));

  Future<Isolate> _getIsolate(String isolateId) {
    return captureElapsedTime(() async {
      await isInitialized;
      _checkIsolate('getIsolate', isolateId);
      return inspector.isolate;
    }, (result) => DwdsEvent.getIsolate());
  }

  @override
  Future<MemoryUsage> getMemoryUsage(String isolateId) =>
      wrapInErrorHandlerAsync(
        'getMemoryUsage',
        () => _getMemoryUsage(isolateId),
      );

  Future<MemoryUsage> _getMemoryUsage(String isolateId) async {
    await isInitialized;
    _checkIsolate('getMemoryUsage', isolateId);
    return inspector.getMemoryUsage();
  }

  @override
  Future<Obj> getObject(
    String isolateId,
    String objectId, {
    int? offset,
    int? count,

    /// Note that `idZoneId` arguments will be ignored. This parameter is only
    /// here to make this method is a valid override of
    /// [VmServiceInterface.getObject].
    String? idZoneId,
  }) => wrapInErrorHandlerAsync(
    'getObject',
    () => _getObject(isolateId, objectId, offset: offset, count: count),
  );

  Future<Obj> _getObject(
    String isolateId,
    String objectId, {
    int? offset,
    int? count,
  }) async {
    await isInitialized;
    _checkIsolate('getObject', isolateId);
    return inspector.getObject(objectId, offset: offset, count: count);
  }

  @override
  Future<ScriptList> getScripts(String isolateId) =>
      wrapInErrorHandlerAsync('getScripts', () => _getScripts(isolateId));

  Future<ScriptList> _getScripts(String isolateId) {
    return captureElapsedTime(() async {
      await isInitialized;
      _checkIsolate('getScripts', isolateId);
      return inspector.getScripts();
    }, (result) => DwdsEvent.getScripts());
  }

  @override
  Future<SourceReport> getSourceReport(
    String isolateId,
    List<String> reports, {
    String? scriptId,
    int? tokenPos,
    int? endTokenPos,
    bool? forceCompile,
    bool? reportLines,
    List<String>? libraryFilters,
    // Note: Ignore the optional librariesAlreadyCompiled parameter. It is here
    // to match the VM service interface.
    List<String>? librariesAlreadyCompiled,
  }) => wrapInErrorHandlerAsync(
    'getSourceReport',
    () => _getSourceReport(
      isolateId,
      reports,
      scriptId: scriptId,
      tokenPos: tokenPos,
      endTokenPos: endTokenPos,
      forceCompile: forceCompile,
      reportLines: reportLines,
      libraryFilters: libraryFilters,
    ),
  );

  Future<SourceReport> _getSourceReport(
    String isolateId,
    List<String> reports, {
    String? scriptId,
    int? tokenPos,
    int? endTokenPos,
    bool? forceCompile,
    bool? reportLines,
    List<String>? libraryFilters,
  }) {
    return captureElapsedTime(() async {
      await isInitialized;
      _checkIsolate('getSourceReport', isolateId);
      return await inspector.getSourceReport(
        reports,
        scriptId: scriptId,
        tokenPos: tokenPos,
        endTokenPos: endTokenPos,
        forceCompile: forceCompile,
        reportLines: reportLines,
        libraryFilters: libraryFilters,
      );
    }, (result) => DwdsEvent.getSourceReport());
  }

  /// Returns the current stack.
  ///
  /// Throws RPCError the corresponding isolate is not paused.
  ///
  /// The returned stack will contain up to [limit] frames if provided.
  @override
  Future<Stack> getStack(
    String isolateId, {
    int? limit,

    /// Note that `idZoneId` arguments will be ignored. This parameter is only
    /// here to make this method is a valid override of
    /// [VmServiceInterface.getStack].
    String? idZoneId,
  }) => wrapInErrorHandlerAsync(
    'getStack',
    () => _getStack(isolateId, limit: limit),
  );

  Future<Stack> _getStack(String isolateId, {int? limit}) async {
    await isInitialized;
    await isStarted;
    _checkIsolate('getStack', isolateId);
    return (await debuggerFuture).getStack(limit: limit);
  }

  @override
  Future<VM> getVM() => wrapInErrorHandlerAsync('getVM', _getVM);

  Future<VM> _getVM() {
    return captureElapsedTime(() async {
      await isInitialized;
      return vm;
    }, (result) => DwdsEvent.getVM());
  }

  @override
  Future<Response> invoke(
    String isolateId,
    String targetId,
    String selector,
    List argumentIds, {
    // TODO(798) - respect disableBreakpoints.
    bool? disableBreakpoints,

    /// Note that `idZoneId` arguments will be ignored. This parameter is only
    /// here to make this method is a valid override of
    /// [VmServiceInterface.invoke].
    String? idZoneId,
  }) => wrapInErrorHandlerAsync(
    'invoke',
    () => _invoke(isolateId, targetId, selector, argumentIds),
  );

  Future<Response> _invoke(
    String isolateId,
    String targetId,
    String selector,
    List argumentIds,
  ) async {
    await isInitialized;
    _checkIsolate('invoke', isolateId);
    final remote = await inspector.invoke(targetId, selector, argumentIds);
    return _instanceRef(remote);
  }

  @override
  Stream<Event> onEvent(String streamId) {
    return streamControllers.putIfAbsent(streamId, () {
      switch (streamId) {
        case EventStreams.kExtension:
          return StreamController<Event>.broadcast();
        case EventStreams.kIsolate:
          // TODO: right now we only support the `ServiceExtensionAdded` event
          // for the Isolate stream.
          return StreamController<Event>.broadcast();
        case EventStreams.kVM:
          return StreamController<Event>.broadcast();
        case EventStreams.kGC:
          return StreamController<Event>.broadcast();
        case EventStreams.kTimeline:
          return StreamController<Event>.broadcast();
        case EventStreams.kService:
          return StreamController<Event>.broadcast();
        case EventStreams.kDebug:
          return StreamController<Event>.broadcast();
        case EventStreams.kLogging:
          return StreamController<Event>.broadcast();
        case EventStreams.kStdout:
          return _chromeConsoleStreamController(
            (e) => _stdoutTypes.contains(e.type),
          );
        case EventStreams.kStderr:
          return _chromeConsoleStreamController(
            (e) => _stderrTypes.contains(e.type),
            includeExceptions: true,
          );
        default:
          throw RPCError(
            'streamListen',
            RPCErrorKind.kInvalidParams.code,
            'The stream `$streamId` is not supported on web devices',
          );
      }
    }).stream;
  }

  @override
  Future<Success> pause(String isolateId) =>
      wrapInErrorHandlerAsync('pause', () => _pause(isolateId));

  Future<Success> _pause(String isolateId) async {
    await isInitialized;
    _checkIsolate('pause', isolateId);
    return (await debuggerFuture).pause();
  }

  // Note: Ignore the optional local parameter, when it is set to `true` the
  // request is intercepted and handled by DDS.
  @override
  Future<UriList> lookupResolvedPackageUris(
    String isolateId,
    List<String> uris, {
    bool? local,
  }) => wrapInErrorHandlerAsync(
    'lookupResolvedPackageUris',
    () => _lookupResolvedPackageUris(isolateId, uris),
  );

  Future<UriList> _lookupResolvedPackageUris(
    String isolateId,
    List<String> uris,
  ) async {
    await isInitialized;
    _checkIsolate('lookupResolvedPackageUris', isolateId);
    return UriList(uris: uris.map(DartUri.toResolvedUri).toList());
  }

  @override
  Future<UriList> lookupPackageUris(String isolateId, List<String> uris) =>
      wrapInErrorHandlerAsync(
        'lookupPackageUris',
        () => _lookupPackageUris(isolateId, uris),
      );

  Future<UriList> _lookupPackageUris(
    String isolateId,
    List<String> uris,
  ) async {
    await isInitialized;
    _checkIsolate('lookupPackageUris', isolateId);
    return UriList(uris: uris.map(DartUri.toPackageUri).toList());
  }

  @override
  Future<Success> registerService(String service, String alias) {
    return rpcNotSupportedFuture('registerService');
  }

  @override
  Future<ReloadReport> reloadSources(
    String isolateId, {
    bool? force,
    bool? pause,
    String? rootLibUri,
    String? packagesUri,
  }) async {
    await isInitialized;
    _checkIsolate('reloadSources', isolateId);

    ReloadReport getFailedReloadReport(String error) =>
        _ReloadReportWithMetadata(success: false)
          ..json = {
            'notices': [
              {'message': error},
            ],
          };
    try {
      await _performClientSideHotReload(isolateId);
    } catch (e) {
      _logger.info('Hot reload failed: $e');
      return getFailedReloadReport(e.toString());
    }
    _logger.info('Successful hot reload');
    return _ReloadReportWithMetadata(success: true);
  }

  /// Performs a client-side hot reload by fetching libraries, handling
  /// PausePostRequests, and invoking the reload.
  Future<void> _performClientSideHotReload(String isolateId) async {
    _logger.info('Attempting a hot reload');

    final debugger = await debuggerFuture;
    final reloadedSrcs = <String>{};
    final computedReloadedSrcs = Completer<void>();
    final parsedAllReloadedSrcs = Completer<void>();
    // Wait until all the reloaded scripts are parsed before we reinitialize
    // metadata below.
    final parsedScriptsSubscription = debugger.parsedScriptsController.stream
        .listen((url) {
          computedReloadedSrcs.future.then((_) {
            reloadedSrcs.remove(Uri.parse(url).normalizePath().path);
            if (reloadedSrcs.isEmpty) {
              parsedAllReloadedSrcs.complete();
            }
          });
        });

    // Initiate a hot reload.
    _logger.info('Issuing \$dartHotReloadStartDwds request');
    final remoteObject = await inspector.jsEvaluate(
      '\$dartHotReloadStartDwds();',
      awaitPromise: true,
      returnByValue: true,
    );
    final reloadedSrcModuleLibraries = (remoteObject.value as List).cast<Map>();
    final reloadedModulesToLibraries = <String, List<String>>{};
    for (final srcModuleLibrary in reloadedSrcModuleLibraries) {
      final srcModuleLibraryCast = srcModuleLibrary.cast<String, Object>();
      reloadedSrcs.add(
        Uri.parse(srcModuleLibraryCast['src'] as String).normalizePath().path,
      );
      reloadedModulesToLibraries[srcModuleLibraryCast['module'] as String] =
          (srcModuleLibraryCast['libraries'] as List).cast<String>();
    }
    computedReloadedSrcs.complete();
    if (reloadedSrcs.isNotEmpty) await parsedAllReloadedSrcs.future;
    await parsedScriptsSubscription.cancel();

    if (!pauseIsolatesOnStart) {
      // Finish hot reload immediately.
      _logger.info('Issuing \$dartHotReloadEndDwds request');
      await inspector.jsEvaluate(
        '\$dartHotReloadEndDwds();',
        awaitPromise: true,
      );
      _logger.info('\$dartHotReloadEndDwds request complete.');
      // TODO(srujzs): Supposedly Dart DevTools uses a kIsolateReload event
      // for breakpoints? We should confirm and add tests before sending the
      // event.
      return;
    }
    // If `pause_isolates_on_start` is enabled, pause and then the reload
    // should finish later after the client removes breakpoints, reregisters
    // breakpoints, and resumes.
    _finishHotReloadOnResume = () async {
      // Client finished setting breakpoints, called resume, and now the
      // execution has resumed. Finish the hot reload so we start executing
      // the new code instead.
      _logger.info('Issuing \$dartHotReloadEndDwds request');
      await inspector.jsEvaluate(
        '\$dartHotReloadEndDwds();',
        awaitPromise: true,
      );
      _logger.info('\$dartHotReloadEndDwds request complete.');
    };

    // Pause and wait for the pause to occur before managing breakpoints.
    final pausedEvent = _firstStreamEvent('Debug', EventKind.kPauseInterrupted);
    await pause(isolateId);
    await pausedEvent;

    await _reinitializeForHotReload(reloadedModulesToLibraries);

    // This lets the client know that we're ready for breakpoint management
    // and a resume.
    streamNotify(
      'Debug',
      Event(
        kind: EventKind.kPausePostRequest,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isolate: inspector.isolateRef,
      ),
    );
  }

  @override
  Future<Success> removeBreakpoint(String isolateId, String breakpointId) =>
      wrapInErrorHandlerAsync(
        'removeBreakpoint',
        () => _removeBreakpoint(isolateId, breakpointId),
      );

  Future<Success> _removeBreakpoint(
    String isolateId,
    String breakpointId,
  ) async {
    await isInitialized;
    _checkIsolate('removeBreakpoint', isolateId);
    return (await debuggerFuture).removeBreakpoint(breakpointId);
  }

  @override
  Future<Success> resume(String isolateId, {String? step, int? frameIndex}) =>
      wrapInErrorHandlerAsync(
        'resume',
        () => _resume(isolateId, step: step, frameIndex: frameIndex),
      );

  Future<Success> _resume(
    String isolateId, {
    String? step,
    int? frameIndex,
  }) async {
    // If there is a subscriber listening for a resume event after hot-restart,
    // then add the event to the stream and skip processing it.
    if (resumeAfterRestartEventsController.hasListener) {
      resumeAfterRestartEventsController.add(isolateId);
      return Success();
    }

    if (inspector.appConnection.isStarted) {
      await captureElapsedTime(() async {
        await isInitialized;
        await isStarted;
        _checkIsolate('resume', isolateId);
        final debugger = await debuggerFuture;
        return await debugger.resume(step: step, frameIndex: frameIndex);
      }, (result) => DwdsEvent.resume(step));
    } else {
      inspector.appConnection.runMain();
    }
    // Finish the hot reload if needed.
    if (_finishHotReloadOnResume != null) {
      await _finishHotReloadOnResume!();
      _finishHotReloadOnResume = null;
    }
    return Success();
  }

  /// This method is deprecated in vm_service package.
  ///
  /// TODO(annagrin): remove after dart-code and IntelliJ stop using this API.
  /// Issue: https://github.com/dart-lang/webdev/issues/1868
  ///
  // ignore: annotate_overrides
  Future<Success> setExceptionPauseMode(
    String isolateId,
    /*ExceptionPauseMode*/
    String mode,
  ) => setIsolatePauseMode(isolateId, exceptionPauseMode: mode);

  @override
  Future<Success> setIsolatePauseMode(
    String isolateId, {
    String? exceptionPauseMode,
    // TODO(elliette): Is there a way to respect the shouldPauseOnExit parameter
    // in Chrome?
    bool? shouldPauseOnExit,
  }) => wrapInErrorHandlerAsync(
    'setIsolatePauseMode',
    () =>
        _setIsolatePauseMode(isolateId, exceptionPauseMode: exceptionPauseMode),
  );

  Future<Success> _setIsolatePauseMode(
    String isolateId, {
    String? exceptionPauseMode,
  }) async {
    await isInitialized;
    _checkIsolate('setIsolatePauseMode', isolateId);
    return (await debuggerFuture).setExceptionPauseMode(
      exceptionPauseMode ?? ExceptionPauseMode.kNone,
    );
  }

  @override
  Future<Success> setFlag(String name, String value) =>
      wrapInErrorHandlerAsync('setFlag', () => _setFlag(name, value));

  Future<Success> _setFlag(String name, String value) async {
    if (!currentVmServiceFlags.containsKey(name)) {
      return rpcNotSupportedFuture('setFlag');
    }

    assert(value == 'true' || value == 'false');
    currentVmServiceFlags[name] = value == 'true';

    return Success();
  }

  @override
  Future<Success> setLibraryDebuggable(
    String isolateId,
    String libraryId,
    bool isDebuggable,
  ) {
    return rpcNotSupportedFuture('setLibraryDebuggable');
  }

  @override
  Future<Success> setName(String isolateId, String name) =>
      wrapInErrorHandlerAsync('setName', () => _setName(isolateId, name));

  Future<Success> _setName(String isolateId, String name) async {
    await isInitialized;
    _checkIsolate('setName', isolateId);
    inspector.isolate.name = name;
    return Success();
  }

  @override
  Future<Success> setVMName(String name) =>
      wrapInErrorHandlerAsync('setVMName', () => _setVMName(name));

  Future<Success> _setVMName(String name) async {
    vm.name = name;
    streamNotify(
      'VM',
      Event(
        kind: EventKind.kVMUpdate,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        // We are not guaranteed to have an isolate at this point in time.
        isolate: null,
      )..vm = toVMRef(vm),
    );
    return Success();
  }

  @override
  Future<Success> streamListen(String streamId) =>
      wrapInErrorHandlerAsync('streamListen', () => _streamListen(streamId));

  Future<Success> _streamListen(String streamId) async {
    // TODO: This should return an error if the stream is already being listened
    // to.
    onEvent(streamId);
    return Success();
  }

  /// Returns a streamController that listens for console logs from chrome and
  /// adds all events passing [filter] to the stream.
  StreamController<Event> _chromeConsoleStreamController(
    bool Function(ConsoleAPIEvent) filter, {
    bool includeExceptions = false,
  }) {
    late StreamController<Event> controller;
    StreamSubscription? chromeConsoleSubscription;
    StreamSubscription? exceptionsSubscription;

    // This is an edge case for this lint apparently
    //
    // ignore: join_return_with_assignment
    controller = StreamController<Event>.broadcast(
      onCancel: () {
        chromeConsoleSubscription?.cancel();
        exceptionsSubscription?.cancel();
      },
      onListen: () {
        chromeConsoleSubscription = remoteDebugger.onConsoleAPICalled.listen((
          e,
        ) {
          if (!_isIsolateRunning) return;
          final isolateRef = inspector.isolateRef;
          if (!filter(e)) return;
          final args = e.params?['args'] as List?;
          final item = args?[0] as Map?;
          final value = '${item?["value"]}\n';
          controller.add(
            Event(
                kind: EventKind.kWriteEvent,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                isolate: isolateRef,
              )
              ..bytes = base64.encode(utf8.encode(value))
              ..timestamp = e.timestamp.toInt(),
          );
        });
        if (includeExceptions) {
          exceptionsSubscription = remoteDebugger.onExceptionThrown.listen((
            e,
          ) async {
            if (!_isIsolateRunning) return;
            final isolateRef = inspector.isolateRef;
            var description = e.exceptionDetails.exception?.description;
            if (description != null) {
              description = await inspector.mapExceptionStackTrace(description);
            }
            controller.add(
              Event(
                kind: EventKind.kWriteEvent,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                isolate: isolateRef,
              )..bytes = base64.encode(utf8.encode(description ?? '')),
            );
          });
        }
      },
    );
    return controller;
  }

  /// Parses the [BatchedDebugEvents] and emits corresponding Dart VM Service
  /// protocol [Event]s.
  @override
  void parseBatchedDebugEvents(BatchedDebugEvents debugEvents) {
    for (final debugEvent in debugEvents.events) {
      parseDebugEvent(debugEvent);
    }
  }

  /// Parses the [DebugEvent] and emits a corresponding Dart VM Service
  /// protocol [Event].
  @override
  void parseDebugEvent(DebugEvent debugEvent) {
    if (terminatingIsolates) return;
    if (!_isIsolateRunning) return;
    final isolateRef = inspector.isolateRef;

    streamNotify(
      EventStreams.kExtension,
      Event(
          kind: EventKind.kExtension,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: isolateRef,
        )
        ..extensionKind = debugEvent.kind
        ..extensionData = ExtensionData.parse(
          jsonDecode(debugEvent.eventData) as Map<String, dynamic>,
        ),
    );
  }

  /// Parses the [RegisterEvent] and emits a corresponding Dart VM Service
  /// protocol [Event].
  @override
  void parseRegisterEvent(RegisterEvent registerEvent) {
    if (terminatingIsolates) return;
    if (!_isIsolateRunning) return;

    final isolate = inspector.isolate;
    final isolateRef = inspector.isolateRef;
    final service = registerEvent.eventData;
    isolate.extensionRPCs?.add(service);

    streamNotify(
      EventStreams.kIsolate,
      Event(
        kind: EventKind.kServiceExtensionAdded,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isolate: isolateRef,
      )..extensionRPC = service,
    );
  }

  /// Listens for chrome console events and handles the ones we care about.
  void _setUpChromeConsoleListeners(IsolateRef isolateRef) {
    _consoleSubscription = remoteDebugger.onConsoleAPICalled.listen((
      event,
    ) async {
      if (terminatingIsolates) return;
      if (event.type != 'debug') return;
      if (!_isIsolateRunning) return;

      final isolate = inspector.isolate;
      if (isolateRef.id != isolate.id) return;

      final args = event.args;
      final firstArgValue = (args.isNotEmpty ? args[0].value : null) as String?;
      switch (firstArgValue) {
        case 'dart.developer.inspect':
          // All inspected objects should be real objects.
          if (event.args[1].type != 'object') break;

          final inspectee = await _instanceRef(event.args[1]);
          streamNotify(
            EventStreams.kDebug,
            Event(
                kind: EventKind.kInspect,
                timestamp: DateTime.now().millisecondsSinceEpoch,
                isolate: isolateRef,
              )
              ..inspectee = inspectee
              ..timestamp = event.timestamp.toInt(),
          );
          break;
        case 'dart.developer.log':
          await _handleDeveloperLog(isolateRef, event).catchError(
            (error, stackTrace) => _logger.warning(
              'Error handling developer log:',
              error,
              stackTrace,
            ),
          );
          break;
        default:
          break;
      }
    });
  }

  Future<void> _firstStreamEvent(String streamId, String eventKind) {
    final controller = streamControllers[streamId]!;
    return controller.stream.firstWhere((event) => event.kind == eventKind);
  }

  Future<void> _handleDeveloperLog(
    IsolateRef isolateRef,
    ConsoleAPIEvent event,
  ) async {
    final logObject = event.params?['args'][1] as Map?;
    final objectId = logObject?['objectId'];
    // Always attempt to fetch the full properties instead of relying on
    // `RemoteObject.preview` which only has truncated log messages:
    // https://chromedevtools.github.io/devtools-protocol/tot/Runtime/#type-RemoteObject
    final logParams =
        objectId != null
            ? await _fetchFullLogParams(objectId, logObject: logObject)
            : _fetchAbbreviatedLogParams(logObject);

    final logRecord = LogRecord(
      message: await _instanceRef(logParams['message']),
      loggerName: await _instanceRef(logParams['name']),
      level:
          logParams['level'] != null
              ? int.tryParse(logParams['level']!.value.toString())
              : 0,
      error: await _instanceRef(logParams['error']),
      time: event.timestamp.toInt(),
      sequenceNumber:
          logParams['sequenceNumber'] != null
              ? int.tryParse(logParams['sequenceNumber']!.value.toString())
              : 0,
      stackTrace: await _instanceRef(logParams['stackTrace']),
      zone: await _instanceRef(logParams['zone']),
    );

    streamNotify(
      EventStreams.kLogging,
      Event(
          kind: EventKind.kLogging,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: isolateRef,
        )
        ..logRecord = logRecord
        ..timestamp = event.timestamp.toInt(),
    );
  }

  Future<Map<String, RemoteObject>> _fetchFullLogParams(
    String objectId, {
    required Map? logObject,
  }) async {
    final logParams = <String, RemoteObject>{};
    for (final property in await inspector.getProperties(objectId)) {
      final name = property.name;
      final value = property.value;
      if (name != null && value != null) {
        logParams[name] = value;
      }
    }

    // If for some reason we don't get the full log params, then return the
    // abbreviated version instead:
    if (logParams.isEmpty) {
      return _fetchAbbreviatedLogParams(logObject);
    }
    return logParams;
  }

  Map<String, RemoteObject> _fetchAbbreviatedLogParams(Map? logObject) {
    final logParams = <String, RemoteObject>{};
    for (final dynamic property in logObject?['preview']?['properties'] ?? []) {
      if (property is Map<String, dynamic> && property['name'] != null) {
        logParams[property['name'] as String] = RemoteObject(property);
      }
    }
    return logParams;
  }

  @override
  Future<void> yieldControlToDDS(String uri) async {
    final canYield = ChromeDebugService.yieldControlToDDS(uri);

    if (!canYield) {
      throw RPCError(
        'yieldControlToDDS',
        RPCErrorKind.kFeatureDisabled.code,
        'Existing VM service clients prevent DDS from taking control.',
      );
    }
  }

  Future<InstanceRef> _instanceRef(RemoteObject? obj) async {
    final instance = obj == null ? null : await inspector.instanceRefFor(obj);
    return instance ?? InstanceHelper.kNullInstanceRef;
  }

  /// Validate that isolateId matches the current isolate we're connected to and
  /// return that isolate.
  ///
  /// This is useful to call at the beginning of API methods that are passed an
  /// isolate id.
  Isolate _checkIsolate(String methodName, String? isolateId) {
    final currentIsolateId = inspector.isolate.id;
    if (currentIsolateId == null) {
      throw StateError('No running isolate ID');
    }
    if (isolateId != currentIsolateId) {
      _throwSentinel(
        methodName,
        SentinelKind.kCollected,
        'Unrecognized isolateId: $isolateId',
      );
    }
    return inspector.isolate;
  }

  static Never _throwSentinel(String method, String kind, String message) {
    final data = <String, String>{'kind': kind, 'valueAsString': message};
    throw SentinelException.parse(method, data);
  }
}

// The default `ReloadReport`'s `toJson` only emits the type and success of the
// operation. Override it to expose additional possible metadata in the `json`.
// This then gets called in the VM service code that handles request and
// responses.
class _ReloadReportWithMetadata extends ReloadReport {
  _ReloadReportWithMetadata({super.success});

  @override
  Map<String, dynamic> toJson() {
    final jsonified = <String, Object?>{
      'type': type,
      'success': success ?? false,
    };
    // Include any other metadata we may have included in `json`, potentially
    // even overriding the above defaults.
    for (final jsonKey in super.json?.keys ?? <String>[]) {
      jsonified[jsonKey] = super.json![jsonKey];
    }
    return jsonified;
  }
}

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stderr` logs.
const _stderrTypes = ['error'];

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stdout` logs.
const _stdoutTypes = ['log', 'info', 'warning'];
