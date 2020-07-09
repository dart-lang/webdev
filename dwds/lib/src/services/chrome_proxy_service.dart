// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart' hide LogRecord;
import 'package:pedantic/pedantic.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../connections/app_connection.dart';
import '../debugging/debugger.dart';
import '../debugging/execution_context.dart';
import '../debugging/inspector.dart';
import '../debugging/instance.dart';
import '../debugging/location.dart';
import '../debugging/metadata/provider.dart';
import '../debugging/modules.dart';
import '../debugging/remote_debugger.dart';
import '../loaders/strategy.dart';
import '../readers/asset_reader.dart';
import '../utilities/dart_uri.dart';
import '../utilities/shared.dart';
import 'expression_compiler.dart';
import 'expression_evaluator.dart';

/// Adds [event] to the stream with [streamId] if there is anybody listening
/// on that stream.
typedef StreamNotify = void Function(String streamId, Event event);

/// Returns the [AppInspector] for the current tab.
///
/// This may be null during a hot restart or page refresh.
typedef AppInspectorProvider = AppInspector Function();

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService implements VmServiceInterface {
  /// Cache of all existing StreamControllers.
  ///
  /// These are all created through [onEvent].
  final _streamControllers = <String, StreamController<Event>>{};

  /// The root `VM` instance. There can only be one of these, but its isolates
  /// are dynamic and roughly map to chrome tabs.
  final VM _vm;

  final _initializedCompleter = Completer<void>();

  Future<void> get isInitialized => _initializedCompleter.future;

  /// The root URI at which we're serving.
  final String uri;

  final RemoteDebugger remoteDebugger;
  final ExecutionContext executionContext;

  /// Provides debugger-related functionality.
  Future<Debugger> get _debugger => _debuggerCompleter.future;

  final AssetReader _assetReader;

  final Locations _locations;

  final MetadataProvider _metadataProvider;

  final Modules _modules;

  final _debuggerCompleter = Completer<Debugger>();

  AppInspector _inspector;

  /// Public only for testing.
  ///
  /// Returns the [AppInspector] this service uses.
  AppInspector appInspectorProvider() => _inspector;

  StreamSubscription<ConsoleAPIEvent> _consoleSubscription;

  /// If breakpoints should be restored upon a reload / hot restart.
  final bool _restoreBreakpoints;
  final _disabledBreakpoints = <Breakpoint>{};
  final _previousBreakpoints = <Breakpoint>{};

  final LogWriter _logWriter;
  ExpressionEvaluator _expressionEvaluator;

  ChromeProxyService._(
    this._vm,
    this.uri,
    this._assetReader,
    this.remoteDebugger,
    this._metadataProvider,
    this._modules,
    this._locations,
    this._restoreBreakpoints,
    this.executionContext,
    this._logWriter,
  ) {
    _debuggerCompleter.complete(Debugger.create(
      remoteDebugger,
      _streamNotify,
      appInspectorProvider,
      _assetReader,
      _modules,
      _locations,
      uri,
    ));
  }

  static Future<ChromeProxyService> create(
      RemoteDebugger remoteDebugger,
      String tabUrl,
      AssetReader assetReader,
      LoadStrategy loadStrategy,
      MetadataProvider metadataProvider,
      AppConnection appConnection,
      LogWriter logWriter,
      bool restoreBreakpoints,
      ExecutionContext executionContext,
      ExpressionCompiler expressionCompiler) async {
    final vm = VM(
      name: 'ChromeDebugProxy',
      operatingSystem: Platform.operatingSystem,
      startTime: DateTime.now().millisecondsSinceEpoch,
      version: Platform.version,
      isolates: [],
      isolateGroups: [],
      targetCPU: 'Web',
      hostCPU: 'DWDS',
      architectureBits: -1,
      pid: -1,
    );

    var modules = Modules(metadataProvider, tabUrl);
    var locations = Locations(assetReader, modules, tabUrl);
    var service = ChromeProxyService._(
        vm,
        tabUrl,
        assetReader,
        remoteDebugger,
        metadataProvider,
        modules,
        locations,
        restoreBreakpoints,
        executionContext,
        logWriter);
    unawaited(service.createIsolate(appConnection));
    await service.createEvaluator(expressionCompiler);
    return service;
  }

  /// Creates expression evaluator to use in [evaluateInFrame]
  ///
  /// Expression evaluation is only supported with scenarios that
  /// provide non-null [ExpressionCompiler] to [create].
  /// Otherwise [evaluateInFrame] will throw unsupported exception.
  Future<void> createEvaluator(ExpressionCompiler compiler) async {
    _expressionEvaluator = compiler == null
        ? null
        : ExpressionEvaluator(
            await _debugger, _locations, _modules, compiler, _logWriter);
  }

  /// Creates a new isolate.
  ///
  /// Only one isolate at a time is supported, but they should be cleaned up
  /// with [destroyIsolate] and recreated with this method there is a hot
  /// restart or full page refresh.
  Future<void> createIsolate(AppConnection appConnection) async {
    if (_inspector?.isolate != null) {
      throw UnsupportedError(
          'Cannot create multiple isolates for the same app');
    }

    _locations.clearCache();

    await _metadataProvider.initialize(appConnection.request.entrypointPath);
    _modules.initialize();
    (await _debugger).notifyPausedAtStart();
    _inspector = await AppInspector.initialize(
      appConnection,
      remoteDebugger,
      _metadataProvider,
      _assetReader,
      _locations,
      uri,
      await _debugger,
      executionContext,
    );
    for (var breakpoint in _previousBreakpoints) {
      var lineNumber = lineNumberFor(breakpoint);
      var oldRef = (breakpoint.location as SourceLocation).script;
      var dartUri = DartUri(oldRef.uri, uri);
      var newRef = await _inspector.scriptRefFor(dartUri.serverPath);
      await (await _debugger)
          .addBreakpoint(_inspector.isolate.id, newRef.id, lineNumber);
    }

    unawaited(appConnection.onStart.then((_) async {
      await (await _debugger).resumeFromStart();
    }));

    var isolateRef = _inspector.isolateRef;
    var timestamp = DateTime.now().millisecondsSinceEpoch;

    // Listen for `registerExtension` and `postEvent` calls.
    _setUpChromeConsoleListeners(isolateRef);

    _vm.isolates.add(isolateRef);

    _streamNotify(
        'Isolate',
        Event(
            kind: EventKind.kIsolateStart,
            timestamp: timestamp,
            isolate: isolateRef));
    _streamNotify(
        'Isolate',
        Event(
            kind: EventKind.kIsolateRunnable,
            timestamp: timestamp,
            isolate: isolateRef));

    // TODO: We shouldn't need to fire these events since they exist on the
    // isolate, but devtools doesn't recognize extensions after a page refresh
    // otherwise.
    for (var extensionRpc in _inspector.isolate.extensionRPCs) {
      _streamNotify(
          'Isolate',
          Event(
              kind: EventKind.kServiceExtensionAdded,
              timestamp: timestamp,
              isolate: isolateRef)
            ..extensionRPC = extensionRpc);
    }

    // The service is considered initialized when the first isolate is created.
    if (!_initializedCompleter.isCompleted) _initializedCompleter.complete();
  }

  /// Should be called when there is a hot restart or full page refresh.
  ///
  /// Clears out the [_inspector] and all related cached information.
  void destroyIsolate() {
    var isolate = _inspector?.isolate;
    if (isolate == null) return;
    _streamNotify(
        'Isolate',
        Event(
            kind: EventKind.kIsolateExit,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isolate: _inspector.isolateRef));
    _vm.isolates.removeWhere((ref) => ref.id == isolate.id);
    _inspector = null;
    if (_restoreBreakpoints) {
      _previousBreakpoints.clear();
      _previousBreakpoints
        ..addAll(isolate.breakpoints)
        ..addAll(_disabledBreakpoints);
    }
    _consoleSubscription.cancel();
    _consoleSubscription = null;
  }

  Future<void> disableBreakpoints() async {
    _disabledBreakpoints.clear();
    var isolate = _inspector?.isolate;
    if (isolate == null) return;
    _disabledBreakpoints.addAll(isolate.breakpoints);
    for (var breakpoint in isolate.breakpoints.toList()) {
      await (await _debugger).removeBreakpoint(isolate.id, breakpoint.id);
    }
  }

  @override
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
          {int column}) async =>
      (await _debugger)
          .addBreakpoint(isolateId, scriptId, line, column: column);

  @override
  Future<Breakpoint> addBreakpointAtEntry(String isolateId, String functionId) {
    return _rpcNotSupportedFuture('addBreakpointAtEntry');
  }

  @override
  Future<Breakpoint> addBreakpointWithScriptUri(
      String isolateId, String scriptUri, int line,
      {int column}) async {
    var dartUri = DartUri(scriptUri, uri);
    var ref = await _inspector.scriptRefFor(dartUri.serverPath);
    return (await _debugger)
        .addBreakpoint(isolateId, ref.id, line, column: column);
  }

  @override
  Future<Response> callServiceExtension(String method,
      {String isolateId, Map args}) async {
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null) _getIsolate(isolateId);
    args ??= <String, String>{};
    var stringArgs = args.map((k, v) => MapEntry(
        k is String ? k : jsonEncode(k), v is String ? v : jsonEncode(v)));
    var expression = '''
${globalLoadStrategy.loadModuleSnippet}("dart_sdk").developer.invokeExtension(
    "$method", JSON.stringify(${jsonEncode(stringArgs)}));
''';
    var response =
        await remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'awaitPromise': true,
      'contextId': await executionContext.id,
    });
    handleErrorIfPresent(response, evalContents: expression);
    var decodedResponse =
        jsonDecode(response.result['result']['value'] as String)
            as Map<String, dynamic>;
    if (decodedResponse.containsKey('code') &&
        decodedResponse.containsKey('message') &&
        decodedResponse.containsKey('data')) {
      // ignore: only_throw_errors
      throw RPCError(method, decodedResponse['code'] as int,
          decodedResponse['message'] as String, decodedResponse['data'] as Map);
    } else {
      return Response(
          // TODO(grouma): What should the type be?
          type: '')
        ..json = decodedResponse;
    }
  }

  @override
  Future<Success> clearVMTimeline() {
    return _rpcNotSupportedFuture('clearVMTimeline');
  }

  @override
  Future<Response> evaluate(
      String isolateId, String targetId, String expression,
      {Map<String, String> scope, bool disableBreakpoints}) async {
    // TODO(798) - respect disableBreakpoints.
    var remote = await _inspector?.evaluate(isolateId, targetId, expression,
        scope: scope);
    return _inspector?.instanceHelper?.instanceRefFor(remote);
  }

  @override
  Future<Response> evaluateInFrame(
      String isolateId, int frameIndex, String expression,
      {Map<String, String> scope, bool disableBreakpoints}) async {
    if (_expressionEvaluator != null) {
      var isolate = _inspector?.isolate;
      if (isolate?.id != isolateId) {
        // TODO: Throw an RPC error here.
        throw ArgumentError.value(
            isolateId, 'isolateId', 'Unrecognized isolate id');
      }

      try {
        var result = await _expressionEvaluator.evaluateExpression(
            isolateId, frameIndex, expression);

        // Handle compilation errors, internal errors,
        // and reference errors from JavaScript evaluation in chrome
        if (result.type.contains('Error')) {
          if (!result.type.startsWith('CompilationError')) {
            _logWriter(
                Level.WARNING,
                'Failed to evaluate expression \'$expression\': '
                '${result.type}: ${result.value}.');
            _logWriter(
                Level.INFO,
                'Please follow instructions at '
                'https://github.com/dart-lang/webdev/issues/956 '
                'to file a bug.');
          }
          return ErrorRef(
            kind: 'error',
            message: '${result.type}: ${result.value}',
            id: createId(),
          );
        }
        return _inspector?.instanceHelper?.instanceRefFor(result);
      } catch (e, s) {
        // Handle errors that throw exceptions, such as invalid JavaScript
        // generated by the expression evaluator
        _logWriter(
            Level.WARNING, 'Failed to evaluate expression \'$expression\'. ');
        _logWriter(
            Level.INFO,
            'Please follow instructions at '
            'https://github.com/dart-lang/webdev/issues/956 '
            'to file a bug.');
        _logWriter(Level.INFO, '$e:$s');
        return ErrorRef(kind: 'error', message: '<unknown>', id: createId());
      }
    }

    // TODO: Change this to a RPC error.
    throw UnimplementedError(
        'Expression evaluation is not supported for this configuration');
  }

  @override
  Future<AllocationProfile> getAllocationProfile(String isolateId,
      {bool gc, bool reset}) {
    return _rpcNotSupportedFuture('getAllocationProfile');
  }

  @override
  Future<ClassList> getClassList(String isolateId) {
    // See dart-lang/webdev/issues/971.
    return _rpcNotSupportedFuture('getClassList');
  }

  @override
  Future<FlagList> getFlagList() async {
    // VM flags do not apply to web apps.
    return FlagList(flags: []);
  }

  @override
  Future<InstanceSet> getInstances(
      String isolateId, String classId, int limit) {
    return _rpcNotSupportedFuture('getInstances');
  }

  /// Sync version of [getIsolate] for internal use, also has stronger typing
  /// than the public one which has to be dynamic.
  Isolate _getIsolate(String isolateId) {
    var isolate = _inspector?.isolate;
    if (isolate?.id == isolateId) return isolate;
    // TODO: Throw an RPC error here.
    throw ArgumentError.value(
        isolateId, 'isolateId', 'Unrecognized isolate id');
  }

  @override
  Future<Isolate> getIsolate(String isolateId) async => _getIsolate(isolateId);

  @override
  Future<MemoryUsage> getMemoryUsage(String isolateId) {
    return _inspector.getMemoryUsage(isolateId);
  }

  @override
  Future<Obj> getObject(String isolateId, String objectId,
          {int offset, int count}) =>
      _inspector?.getObject(isolateId, objectId, offset: offset, count: count);

  @override
  Future<ScriptList> getScripts(String isolateId) =>
      _inspector?.getScripts(isolateId);

  @override
  Future<SourceReport> getSourceReport(String isolateId, List<String> reports,
      {String scriptId, int tokenPos, int endTokenPos, bool forceCompile}) {
    return _inspector?.getSourceReport(isolateId, reports,
        scriptId: scriptId,
        tokenPos: tokenPos,
        endTokenPos: endTokenPos,
        forceCompile: forceCompile);
  }

  /// Returns the current stack.
  ///
  /// Returns null if the corresponding isolate is not paused.
  @override
  Future<Stack> getStack(String isolateId) async =>
      (await _debugger).getStack(isolateId);

  @override
  Future<VM> getVM() async {
    await isInitialized;
    return _vm;
  }

  @override
  Future<Timeline> getVMTimeline({int timeOriginMicros, int timeExtentMicros}) {
    return _rpcNotSupportedFuture('getVMTimeline');
  }

  @override
  Future<TimelineFlags> getVMTimelineFlags() {
    return _rpcNotSupportedFuture('getVMTimelineFlags');
  }

  @override
  Future<Version> getVersion() async {
    var version = semver.Version.parse(vmServiceVersion);
    return Version(major: version.major, minor: version.minor);
  }

  @override
  Future<Response> invoke(
      String isolateId, String targetId, String selector, List argumentIds,
      {bool disableBreakpoints}) async {
    // TODO(798) - respect disableBreakpoints.
    var remote =
        await _inspector?.invoke(isolateId, targetId, selector, argumentIds);
    var result = _inspector?.instanceHelper?.instanceRefFor(remote);
    if (result == null) {
      throw ChromeDebugException(
          {'text': 'null result from invoke of $selector'});
    }
    return result;
  }

  @override
  Future<Success> kill(String isolateId) {
    return _rpcNotSupportedFuture('kill');
  }

  @override
  Stream<Event> onEvent(String streamId) {
    return _streamControllers.putIfAbsent(streamId, () {
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
              (e) => _stdoutTypes.contains(e.type));
        case EventStreams.kStderr:
          return _chromeConsoleStreamController(
              (e) => _stderrTypes.contains(e.type),
              includeExceptions: true);
        default:
          throw RPCError(
            'streamListen',
            RPCError.kMethodNotFound,
            'The stream `$streamId` is not supported on web devices',
          );
      }
    }).stream;
  }

  @override
  Future<Success> pause(String isolateId) async => (await _debugger).pause();

  @override
  Future<Success> registerService(String service, String alias) async {
    return _rpcNotSupportedFuture('registerService');
  }

  @override
  Future<ReloadReport> reloadSources(String isolateId,
      {bool force, bool pause, String rootLibUri, String packagesUri}) {
    return Future.error(RPCError(
      'reloadSources',
      RPCError.kMethodNotFound,
      'Hot reload not supported on web devices',
    ));
  }

  @override
  Future<Success> removeBreakpoint(
      String isolateId, String breakpointId) async {
    _disabledBreakpoints
        .removeWhere((breakpoint) => breakpoint.id == breakpointId);
    return (await _debugger).removeBreakpoint(isolateId, breakpointId);
  }

  @override
  Future<Success> resume(String isolateId,
      {String step, int frameIndex}) async {
    if (_inspector.appConnection.isStarted) {
      return await (await _debugger)
          .resume(isolateId, step: step, frameIndex: frameIndex);
    } else {
      _inspector.appConnection.runMain();
      return Success();
    }
  }

  @override
  Future<Success> setExceptionPauseMode(String isolateId, String mode) async {
    return (await _debugger).setExceptionPauseMode(isolateId, mode);
  }

  @override
  Future<Success> setFlag(String name, String value) {
    return _rpcNotSupportedFuture('setFlag');
  }

  @override
  Future<Success> setLibraryDebuggable(
      String isolateId, String libraryId, bool isDebuggable) {
    return _rpcNotSupportedFuture('setLibraryDebuggable');
  }

  @override
  Future<Success> setName(String isolateId, String name) async {
    var isolate = _getIsolate(isolateId);
    isolate.name = name;
    return Success();
  }

  @override
  Future<Success> setVMName(String name) async {
    _vm.name = name;
    _streamNotify(
        'VM',
        Event(
            kind: EventKind.kVMUpdate,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            // We are not guaranteed to have an isolate at this point an time.
            isolate: null)
          ..vm = toVMRef(_vm));
    return Success();
  }

  @override
  Future<Success> setVMTimelineFlags(List<String> recordedStreams) {
    return _rpcNotSupportedFuture('setVMTimelineFlags');
  }

  @override
  Future<Success> streamCancel(String streamId) {
    // TODO: We should implement this (as we've already implemented
    // streamListen).
    return _rpcNotSupportedFuture('streamCancel');
  }

  @override
  Future<Success> streamListen(String streamId) async {
    // TODO: This should return an error if the stream is already being listened
    // to.
    onEvent(streamId);
    return Success();
  }

  @override
  Future<Success> clearCpuSamples(String isolateId) {
    return _rpcNotSupportedFuture('clearCpuSamples');
  }

  @override
  Future<CpuSamples> getCpuSamples(
      String isolateId, int timeOriginMicros, int timeExtentMicros) {
    return _rpcNotSupportedFuture('getCpuSamples');
  }

  /// Returns a streamController that listens for console logs from chrome and
  /// adds all events passing [filter] to the stream.
  StreamController<Event> _chromeConsoleStreamController(
      bool Function(ConsoleAPIEvent) filter,
      {bool includeExceptions = false}) {
    StreamController<Event> controller;
    StreamSubscription chromeConsoleSubscription;
    StreamSubscription exceptionsSubscription;

    // This is an edge case for this lint apparently
    //
    // ignore: join_return_with_assignment
    controller = StreamController<Event>.broadcast(onCancel: () {
      chromeConsoleSubscription?.cancel();
      exceptionsSubscription?.cancel();
    }, onListen: () {
      chromeConsoleSubscription = remoteDebugger.onConsoleAPICalled.listen((e) {
        var isolate = _inspector?.isolate;
        if (isolate == null) return;
        if (!filter(e)) return;
        var args = e.params['args'] as List;
        var item = args[0] as Map;
        var value = '${item["value"]}\n';
        controller.add(Event(
            kind: EventKind.kWriteEvent,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            isolate: _inspector.isolateRef)
          ..bytes = base64.encode(utf8.encode(value))
          ..timestamp = e.timestamp.toInt());
      });
      if (includeExceptions) {
        exceptionsSubscription = remoteDebugger.onExceptionThrown.listen((e) {
          var isolate = _inspector?.isolate;
          if (isolate == null) return;
          controller.add(Event(
              kind: EventKind.kWriteEvent,
              timestamp: DateTime.now().millisecondsSinceEpoch,
              isolate: _inspector.isolateRef)
            ..bytes = base64.encode(
                utf8.encode(e.exceptionDetails.exception.description ?? '')));
        });
      }
    });
    return controller;
  }

  /// Listens for chrome console events and handles the ones we care about.
  void _setUpChromeConsoleListeners(IsolateRef isolateRef) {
    _consoleSubscription =
        remoteDebugger.onConsoleAPICalled.listen((event) async {
      if (event.type != 'debug') return;

      var isolate = _inspector?.isolate;
      if (isolate == null) return;

      var firstArgValue = event.args[0].value as String;
      switch (firstArgValue) {
        case 'dart.developer.registerExtension':
          var service = event.args[1].value as String;
          isolate.extensionRPCs.add(service);
          _streamNotify(
              EventStreams.kIsolate,
              Event(
                  kind: EventKind.kServiceExtensionAdded,
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  isolate: isolateRef)
                ..extensionRPC = service);
          break;
        case 'dart.developer.postEvent':
          _streamNotify(
              EventStreams.kExtension,
              Event(
                  kind: EventKind.kExtension,
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  isolate: isolateRef)
                ..extensionKind = event.args[1].value as String
                ..extensionData = ExtensionData.parse(
                    jsonDecode(event.args[2].value as String) as Map));
          break;
        case 'dart.developer.inspect':
          // All inspected objects should be real objects.
          if (event.args[1].type != 'object') break;

          var inspectee =
              await _inspector.instanceHelper.instanceRefFor(event.args[1]);
          _streamNotify(
              EventStreams.kDebug,
              Event(
                  kind: EventKind.kInspect,
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  isolate: isolateRef)
                ..inspectee = inspectee
                ..timestamp = event.timestamp.toInt());
          break;
        case 'dart.developer.log':
          _handleDeveloperLog(isolateRef, event);
          break;
        default:
          break;
      }
    });
  }

  void _streamNotify(String streamId, Event event) {
    var controller = _streamControllers[streamId];
    if (controller == null) return;
    controller.add(event);
  }

  void _handleDeveloperLog(IsolateRef isolateRef, ConsoleAPIEvent event) async {
    var logObject = event.params['args'][1] as Map;
    var logParams = <String, RemoteObject>{};
    for (dynamic obj in logObject['preview']['properties']) {
      if (obj['name'] != null && obj is Map<String, dynamic>) {
        logParams[obj['name'] as String] = RemoteObject(obj);
      }
    }

    var logRecord = LogRecord(
      message: await _instanceRef(logParams['message']),
      loggerName: await _instanceRef(logParams['name']),
      level: logParams['level'] != null
          ? int.tryParse(logParams['level'].value.toString())
          : 0,
      error: await _instanceRef(logParams['error']),
      time: event.timestamp.toInt(),
      sequenceNumber: logParams['sequenceNumber'] != null
          ? int.tryParse(logParams['sequenceNumber'].value.toString())
          : 0,
      stackTrace: await _instanceRef(logParams['stackTrace']),
      zone: await _instanceRef(logParams['zone']),
    );

    _streamNotify(
      EventStreams.kLogging,
      Event(
          kind: EventKind.kLogging,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: isolateRef)
        ..logRecord = logRecord
        ..timestamp = event.timestamp.toInt(),
    );
  }

  @override
  Future<Timestamp> getVMTimelineMicros() {
    return _rpcNotSupportedFuture('getVMTimelineMicros');
  }

  @override
  Future<InboundReferences> getInboundReferences(
      String isolateId, String targetId, int limit) {
    return _rpcNotSupportedFuture('getInboundReferences');
  }

  @override
  Future<RetainingPath> getRetainingPath(
      String isolateId, String targetId, int limit) {
    return _rpcNotSupportedFuture('getRetainingPath');
  }

  @override
  Future<Success> requestHeapSnapshot(String isolateId) {
    return _rpcNotSupportedFuture('requestHeapSnapshot');
  }

  @override
  Future<IsolateGroup> getIsolateGroup(String isolateGroupId) {
    return _rpcNotSupportedFuture('getIsolateGroup');
  }

  @override
  Future<MemoryUsage> getIsolateGroupMemoryUsage(String isolateGroupId) {
    return _rpcNotSupportedFuture('getIsolateGroupMemoryUsage');
  }

  @override
  Future<ClientName> getClientName() {
    return _rpcNotSupportedFuture('getClientName');
  }

  @override
  Future<Success> setClientName(String name) {
    return _rpcNotSupportedFuture('setClientName');
  }

  @override
  Future<Success> requirePermissionToResume(
      {bool onPauseStart, bool onPauseReload, bool onPauseExit}) {
    return _rpcNotSupportedFuture('requirePermissionToResume');
  }

  @override
  Future<ProtocolList> getSupportedProtocols() async {
    var version = semver.Version.parse(vmServiceVersion);
    return ProtocolList(protocols: [
      Protocol(
        protocolName: 'VM Service',
        major: version.major,
        minor: version.minor,
      )
    ]);
  }

  Future<InstanceRef> _instanceRef(RemoteObject obj) async {
    if (obj == null) {
      return InstanceHelper.kNullInstanceRef;
    } else {
      return _inspector.instanceHelper.instanceRefFor(obj);
    }
  }

  static RPCError _rpcNotSupported(String method) {
    return RPCError(
        method, RPCError.kMethodNotFound, 'Not supported on web devices');
  }

  static Future<T> _rpcNotSupportedFuture<T>(String method) {
    return Future.error(_rpcNotSupported(method));
  }
}

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stderr` logs.
const _stderrTypes = ['error'];

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stdout` logs.
const _stdoutTypes = ['log', 'info', 'warning'];

class ChromeDebugException extends ExceptionDetails implements Exception {
  /// Optional, additional information about the exception.
  final Object additionalDetails;

  /// Optional, the exact contents of the eval that was attempted.
  final String evalContents;

  ChromeDebugException(Map<String, dynamic> exceptionDetails,
      {this.additionalDetails, this.evalContents})
      : super(exceptionDetails);

  @override
  String toString() {
    var description = StringBuffer()
      ..writeln('Unexpected error from chrome devtools:');
    if (text != null) {
      description.writeln('text: $text');
    }
    if (exception != null) {
      description.writeln('exception:');
      description.writeln('  description: ${exception.description}');
      description.writeln('  type: ${exception.type}');
      description.writeln('  value: ${exception.value}');
    }
    if (evalContents != null) {
      description.writeln('attempted JS eval: `$evalContents`');
    }
    if (additionalDetails != null) {
      description.writeln('additional details:\n  $additionalDetails');
    }
    return description.toString();
  }
}
