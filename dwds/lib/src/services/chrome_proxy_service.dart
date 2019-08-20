// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../dwds.dart' show LogWriter;
import '../debugging/debugger.dart';
import '../debugging/inspector.dart';
import '../debugging/remote_debugger.dart';
import '../handlers/asset_handler.dart';
import '../utilities/dart_uri.dart';
import '../utilities/shared.dart';

/// Adds [event] to the stream with [streamId] if there is anybody listening
/// on that stream.
typedef StreamNotify = void Function(String streamId, Event event);

/// Returns the [AppInspector] for the current tab.
///
/// This may be null during a hot restart or page refresh.
typedef AppInspectorProvider = AppInspector Function();

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService implements VmServiceInterface {
  final LogWriter _logWriter;

  /// Cache of all existing StreamControllers.
  ///
  /// These are all created through [onEvent].
  final _streamControllers = <String, StreamController<Event>>{};

  /// The root `VM` instance. There can only be one of these, but its isolates
  /// are dynamic and roughly map to chrome tabs.
  final VM _vm;

  /// The root URI at which we're serving.
  final String uri;

  final RemoteDebugger remoteDebugger;

  final AssetHandler _assetHandler;

  /// Provides debugger-related functionality.
  Debugger _debugger;

  AppInspector _inspector;

  /// Public only for testing.
  ///
  /// Returns the [AppInspector] this service uses.
  AppInspector appInspectorProvider() => _inspector;

  StreamSubscription<ConsoleAPIEvent> _consoleSubscription;

  ChromeProxyService._(
    this._vm,
    this.uri,
    this._assetHandler,
    this.remoteDebugger,
    this._logWriter,
  );

  static Future<ChromeProxyService> create(
    RemoteDebugger remoteDebugger,
    String tabUrl,
    AssetHandler assetHandler,
    String appInstanceId,
    LogWriter logWriter,
  ) async {
    // TODO: What about `architectureBits`, `targetCPU`, `hostCPU` and `pid`?
    final vm = VM()
      ..isolates = []
      ..name = 'ChromeDebugProxy'
      ..startTime = DateTime.now().millisecondsSinceEpoch
      ..version = Platform.version;
    var service = ChromeProxyService._(
        vm, tabUrl, assetHandler, remoteDebugger, logWriter);
    await service._initialize();
    await service.createIsolate();
    return service;
  }

  Future<Null> _initialize() async {
    _debugger = await Debugger.create(
      _assetHandler,
      remoteDebugger,
      _streamNotify,
      appInspectorProvider,
      uri,
      _logWriter,
    );
  }

  /// Creates a new isolate.
  ///
  /// Only one isolate at a time is supported, but they should be cleaned up
  /// with [destroyIsolate] and recreated with this method when there is a hot
  /// restart or full page refresh.
  Future<void> createIsolate() async {
    if (_inspector?.isolate != null) {
      throw UnsupportedError(
          'Cannot create multiple isolates for the same app');
    }

    _inspector = await AppInspector.initialize(
      remoteDebugger,
      _assetHandler,
      _debugger,
      uri,
    );

    var isolateRef = _inspector.isolateRef;

    // Listen for `registerExtension` and `postEvent` calls.
    _setUpChromeConsoleListeners(isolateRef);

    _vm.isolates.add(isolateRef);

    _streamNotify(
        'Isolate',
        Event()
          ..kind = EventKind.kIsolateStart
          ..isolate = isolateRef);
    _streamNotify(
        'Isolate',
        Event()
          ..kind = EventKind.kIsolateRunnable
          ..isolate = isolateRef);

    // TODO: We shouldn't need to fire these events since they exist on the
    // isolate, but devtools doesn't recognize extensions after a page refresh
    // otherwise.
    for (var extensionRpc in _inspector.isolate.extensionRPCs) {
      _streamNotify(
          'Isolate',
          Event()
            ..kind = EventKind.kServiceExtensionAdded
            ..extensionRPC = extensionRpc
            ..isolate = isolateRef);
    }
  }

  /// Should be called when there is a hot restart or full page refresh.
  ///
  /// Clears out the [_inspector] and all related cached information.
  void destroyIsolate() {
    var isolate = _inspector?.isolate;
    if (isolate == null) return;
    _streamNotify(
        'Isolate',
        Event()
          ..kind = EventKind.kIsolateExit
          ..isolate = _inspector.isolateRef);
    _vm.isolates.removeWhere((ref) => ref.id == isolate.id);
    _inspector = null;
    _consoleSubscription.cancel();
    _consoleSubscription = null;
  }

  @override
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
          {int column}) =>
      _debugger.addBreakpoint(isolateId, scriptId, line, column: column);

  @override
  Future<Breakpoint> addBreakpointAtEntry(String isolateId, String functionId) {
    throw UnimplementedError();
  }

  @override
  Future<Breakpoint> addBreakpointWithScriptUri(
      String isolateId, String scriptUri, int line,
      {int column}) async {
    var dartUri = DartUri(scriptUri, uri);
    var ref = await _inspector.scriptRefFor(dartUri.serverPath);
    return _debugger.addBreakpoint(isolateId, ref.id, line, column: column);
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
require("dart_sdk").developer.invokeExtension(
    "$method", JSON.stringify(${jsonEncode(stringArgs)}));
''';
    var response =
        await remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'awaitPromise': true,
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
      return Response()..json = decodedResponse;
    }
  }

  @override
  Future<Success> clearVMTimeline() {
    throw UnimplementedError();
  }

  @override
  Future evaluate(String isolateId, String targetId, String expression,
      {Map<String, String> scope, bool disableBreakpoints}) async {
    var remote = await _inspector?.evaluate(isolateId, targetId, expression,
        scope: scope, disableBreakpoints: disableBreakpoints);
    return _inspector?.instanceHelper?.instanceRefFor(remote);
  }

  @override
  Future evaluateInFrame(String isolateId, int frameIndex, String expression,
      {Map<String, String> scope, bool disableBreakpoints}) {
    throw UnimplementedError();
  }

  @override
  Future<AllocationProfile> getAllocationProfile(String isolateId,
      {bool gc, bool reset}) {
    throw UnimplementedError();
  }

  @override
  Future<FlagList> getFlagList() {
    throw UnimplementedError();
  }

  @override
  Future<InstanceSet> getInstances(
      String isolateId, String classId, int limit) {
    throw UnimplementedError();
  }

  /// Sync version of [getIsolate] for internal use, also has stronger typing
  /// than the public one which has to be dynamic.
  Isolate _getIsolate(String isolateId) {
    var isolate = _inspector?.isolate;
    if (isolate?.id == isolateId) return isolate;
    throw ArgumentError.value(
        isolateId, 'isolateId', 'Unrecognized isolate id');
  }

  @override
  Future<Isolate> getIsolate(String isolateId) async => _getIsolate(isolateId);

  @override
  Future<dynamic> getMemoryUsage(String isolateId) async {
    throw UnimplementedError();
  }

  @override
  Future getObject(String isolateId, String objectId,
          {int offset, int count}) =>
      _inspector?.getObject(isolateId, objectId, offset: offset, count: count);

  @override
  Future<ScriptList> getScripts(String isolateId) =>
      _inspector?.getScripts(isolateId);

  @override
  Future<SourceReport> getSourceReport(String isolateId, List<String> reports,
      {String scriptId, int tokenPos, int endTokenPos, bool forceCompile}) {
    throw UnimplementedError();
  }

  /// Returns the current stack.
  ///
  /// Returns null if the corresponding isolate is not paused.
  @override
  Future<Stack> getStack(String isolateId) => _debugger.getStack(isolateId);

  @override
  Future<VM> getVM() => Future.value(_vm);

  @override
  Future<Timeline> getVMTimeline({int timeOriginMicros, int timeExtentMicros}) {
    throw UnimplementedError();
  }

  @override
  Future<TimelineFlags> getVMTimelineFlags() {
    throw UnimplementedError();
  }

  @override
  Future<Version> getVersion() async {
    var version = semver.Version.parse(vmServiceVersion);
    return Version()
      ..major = version.major
      ..minor = version.minor;
  }

  @override
  Future invoke(
      String isolateId, String targetId, String selector, List argumentIds,
      {bool disableBreakpoints}) {
    throw UnimplementedError();
  }

  @override
  Future<Success> kill(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Stream<Event> onEvent(String streamId) {
    return _streamControllers.putIfAbsent(streamId, () {
      switch (streamId) {
        case 'Extension':
        // TODO: right now we only support the `ServiceExtensionAdded` event for
        // the Isolate stream.
        case 'Isolate':
        case 'VM':
        // TODO: https://github.com/dart-lang/webdev/issues/168
        case 'GC':
        // TODO: https://github.com/dart-lang/webdev/issues/168
        case 'Timeline':
        case 'Service':
          return StreamController<Event>.broadcast();
        case 'Debug':
          return StreamController<Event>.broadcast();
        case 'Stdout':
          return _chromeConsoleStreamController(
              (e) => _stdoutTypes.contains(e.type));
        case 'Stderr':
          return _chromeConsoleStreamController(
              (e) => _stderrTypes.contains(e.type),
              includeExceptions: true);
        default:
          throw UnimplementedError('The stream `$streamId` is not supported.');
      }
    }).stream;
  }

  @override
  Future<Success> pause(String isolateId) => _debugger.pause();

  @override
  Future<Success> registerService(String service, String alias) async {
    throw UnimplementedError();
  }

  @override
  Future<ReloadReport> reloadSources(String isolateId,
      {bool force, bool pause, String rootLibUri, String packagesUri}) async {
    throw UnimplementedError();
  }

  @override
  Future<Success> removeBreakpoint(String isolateId, String breakpointId) =>
      _debugger.removeBreakpoint(isolateId, breakpointId);

  @override
  Future<Success> resume(String isolateId,
          {String step, int frameIndex}) async =>
      _debugger.resume(isolateId, step: step, frameIndex: frameIndex);

  @override
  Future<Success> setExceptionPauseMode(String isolateId, String mode) =>
      _debugger.setExceptionPauseMode(isolateId, mode);

  @override
  Future<Success> setFlag(String name, String value) {
    throw UnimplementedError();
  }

  @override
  Future<Success> setLibraryDebuggable(
      String isolateId, String libraryId, bool isDebuggable) {
    throw UnimplementedError();
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
        Event()
          ..kind = EventKind.kVMUpdate
          ..vm = toVMRef(_vm));
    return Success();
  }

  @override
  Future<Success> setVMTimelineFlags(List<String> recordedStreams) {
    throw UnimplementedError();
  }

  @override
  Future<Success> streamCancel(String streamId) {
    throw UnimplementedError();
  }

  @override
  Future<Success> streamListen(String streamId) async {
    onEvent(streamId);
    return Success();
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
        controller.add(Event()
          ..kind = EventKind.kWriteEvent
          ..isolate = _inspector.isolateRef
          ..bytes = base64.encode(utf8.encode(value))
          ..timestamp = e.timestamp.toInt());
      });
      if (includeExceptions) {
        exceptionsSubscription = remoteDebugger.onExceptionThrown.listen((e) {
          var isolate = _inspector?.isolate;
          if (isolate == null) return;
          controller.add(Event()
            ..kind = EventKind.kWriteEvent
            ..isolate = _inspector.isolateRef
            ..bytes = base64
                .encode(utf8.encode(e.exceptionDetails.exception.description)));
        });
      }
    });
    return controller;
  }

  /// Listens for chrome console events and handles the ones we care about.
  void _setUpChromeConsoleListeners(IsolateRef isolateRef) {
    _consoleSubscription = remoteDebugger.onConsoleAPICalled.listen((event) {
      var isolate = _inspector?.isolate;
      if (isolate == null) return;
      if (event.type != 'debug') return;
      var firstArgValue = event.args[0].value as String;
      switch (firstArgValue) {
        case 'dart.developer.registerExtension':
          var service = event.args[1].value as String;
          isolate.extensionRPCs.add(service);
          _streamNotify(
              'Isolate',
              Event()
                ..kind = EventKind.kServiceExtensionAdded
                ..extensionRPC = service
                ..isolate = isolateRef);
          break;
        case 'dart.developer.postEvent':
          _streamNotify(
              'Extension',
              Event()
                ..kind = EventKind.kExtension
                ..extensionKind = event.args[1].value as String
                ..extensionData = ExtensionData.parse(
                    jsonDecode(event.args[2].value as String) as Map)
                ..isolate = isolateRef);
          break;
        case 'dart.developer.inspect':
          // All inspected objects should be real objects.
          if (event.args[1].type != 'object') break;

          var inspectee = InstanceRef()
            ..kind = InstanceKind.kPlainInstance
            ..id = event.args[1].objectId
            // TODO(jakemac): Create a real ClassRef, we need a way of looking
            // up the library for a given instance to create it though.
            // https://github.com/dart-lang/sdk/issues/36771.
            ..classRef = ClassRef();
          _streamNotify(
              'Debug',
              Event()
                ..kind = EventKind.kInspect
                ..inspectee = inspectee
                ..timestamp = event.timestamp.toInt()
                ..isolate = isolateRef);
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

  @override
  Future<Timestamp> getVMTimelineMicros() {
    throw UnimplementedError();
  }

  @override
  Future getInboundReferences(String isolateId, String targetId, int limit) {
    throw UnimplementedError();
  }

  @override
  Future<RetainingPath> getRetainingPath(
      String isolateId, String targetId, int limit) {
    throw UnimplementedError();
  }
}

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stderr` logs.
const _stderrTypes = ['error'];

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stdout` logs.
const _stdoutTypes = ['log', 'info', 'warning'];

/// Throws an [ExceptionDetails] object if `exceptionDetails` is present on the
/// result.
void handleErrorIfPresent(WipResponse response,
    {String evalContents, Object additionalDetails}) {
  if (response == null) return;
  if (response.result.containsKey('exceptionDetails')) {
    throw ChromeDebugException(
        response.result['exceptionDetails'] as Map<String, dynamic>,
        evalContents: evalContents,
        additionalDetails: additionalDetails);
  }
}

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
