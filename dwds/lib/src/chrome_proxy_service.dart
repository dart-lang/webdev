// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'helpers.dart';

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService implements VmServiceInterface {
  /// The isolate for the current tab.
  final Isolate _isolate;

  /// Cache of all existing StreamControllers.
  ///
  /// These are all created through [onEvent].
  final _streamControllers = <String, StreamController<Event>>{};

  /// The root `VM` instance. There can only be one of these, but its isolates
  /// are dynamic and roughly map to chrome tabs.
  final VM _vm;

  /// The connection with the chrome debug service for the tab.
  final WipConnection _tabConnection;

  ChromeProxyService._(this._vm, this._isolate, this._tabConnection) {
    // Listen for `registerExtension` and `postEvent` calls.
    _tabConnection.runtime.onConsoleAPICalled.listen((ConsoleAPIEvent event) {
      if (event.type != 'debug') return;
      var firstArgValue = event.args[0].value;
      if (firstArgValue == 'dart.developer.registerExtension') {
        var service = event.args[1].value;
        _isolate.extensionRPCs.add(service);
        _streamNotify(
            'Isolate',
            Event()
              ..kind = EventKind.kServiceExtensionAdded
              ..extensionRPC = service);
      } else if (firstArgValue == 'dart.developer.postEvent') {
        _streamNotify(
            'Extension',
            Event()
              ..kind = EventKind.kExtension
              ..extensionKind = event.args[1].value
              ..extensionData =
                  ExtensionData.parse(jsonDecode(event.args[2].value) as Map));
      }
    });
  }

  static Future<ChromeProxyService> create(
      ChromeConnection chromeConnection, String tabUrl) async {
    var tab = await chromeConnection.getTab((tab) => tab.url == tabUrl);
    var id = createId();
    var isolate = Isolate()
      ..id = id
      ..number = id
      ..name = '${tab.url}:main()'
      ..runnable = true
      ..breakpoints = []
      ..libraries = []
      ..extensionRPCs = [];
    var isolateRef = toIsolateRef(isolate);
    isolate.pauseEvent = Event()
      ..kind = EventKind.kResume
      ..isolate = isolateRef;
    var tabConnection = await tab.connect();
    await tabConnection.debugger.enable();
    await tabConnection.runtime.enable();

    // TODO: What about `architectureBits`, `targetCPU`, `hostCPU` and `pid`?
    final vm = VM()
      ..isolates = [isolateRef]
      ..name = 'ChromeDebugProxy'
      ..startTime = DateTime.now().millisecondsSinceEpoch
      ..version = Platform.version;

    return ChromeProxyService._(vm, isolate, tabConnection);
  }

  @override
  Future<Breakpoint> addBreakpoint(String isolateId, String scriptId, int line,
      {int column}) {
    throw UnimplementedError();
  }

  @override
  Future<Breakpoint> addBreakpointAtEntry(String isolateId, String functionId) {
    throw UnimplementedError();
  }

  @override
  Future<Breakpoint> addBreakpointWithScriptUri(
      String isolateId, String scriptUri, int line,
      {int column}) {
    throw UnimplementedError();
  }

  // TODO: Upstream this on the [VmServiceInterface].
  Future<Response> callServiceExtension(String method,
      {String isolateId, Map<String, String> args}) async {
    // Validate the isolate id is correct, _getIsolate throws if not.
    if (isolateId != null) _getIsolate(isolateId);
    args ??= <String, String>{};
    var expression = '''
require("dart_sdk").developer.invokeExtension("$method", JSON.stringify(${jsonEncode(args)}));
''';
    var response =
        await _tabConnection.runtime.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'awaitPromise': true,
    });
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
  Future<Success> clearCpuProfile(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future<Success> clearVMTimeline() {
    throw UnimplementedError();
  }

  @override
  Future<Success> collectAllGarbage(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future evaluate(String isolateId, String targetId, String expression,
      {Map<String, String> scope}) {
    throw UnimplementedError();
  }

  @override
  Future evaluateInFrame(String isolateId, int frameIndex, String expression,
      {Map<String, String> scope}) {
    throw UnimplementedError();
  }

  @override
  Future<AllocationProfile> getAllocationProfile(String isolateId,
      {String gc, bool reset}) {
    throw UnimplementedError();
  }

  @override
  Future<CpuProfile> getCpuProfile(String isolateId, String tags) {
    throw UnimplementedError();
  }

  @override
  Future<FlagList> getFlagList() {
    throw UnimplementedError();
  }

  @override
  Future<ObjRef> getInstances(String isolateId, String classId, int limit) {
    throw UnimplementedError();
  }

  /// Sync version of [getIsolate] for internal use, also has stronger typing
  /// than the public one which has to be dynamic.
  Isolate _getIsolate(String isolateId) {
    if (_isolate.id == isolateId) return _isolate;
    throw ArgumentError.value(
        isolateId, 'isolateId', 'Unrecognized isolate id');
  }

  @override
  Future getIsolate(String isolateId) async => _getIsolate(isolateId);

  @override
  Future getObject(String isolateId, String objectId, {int offset, int count}) {
    throw UnimplementedError();
  }

  @override
  Future<ScriptList> getScripts(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future<SourceReport> getSourceReport(String isolateId, List<String> reports,
      {String scriptId, int tokenPos, int endTokenPos, bool forceCompile}) {
    throw UnimplementedError();
  }

  @override
  Future<Stack> getStack(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future<VM> getVM() => Future.value(_vm);

  @override
  Future<Response> getVMTimeline() {
    throw UnimplementedError();
  }

  @override
  Future<Version> getVersion() {
    throw UnimplementedError();
  }

  @override
  Future invoke(String isolateId, String targetId, String selector,
      List<String> argumentIds) {
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
        case '_Service':
          return StreamController<Event>.broadcast();
        case 'Debug':
          return _debugStreamController();
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
  Future<Success> pause(String isolateId) {
    throw UnimplementedError();
  }

  @override
  // TODO: what does `alias` represent here?
  Future<Success> registerService(String service, String alias) async {
    _isolate.extensionRPCs.add(service);
    _streamNotify(
        '_Service',
        Event()
          ..kind = EventKind.kServiceRegistered
          ..extensionRPC = service);
    return Success();
  }

  @override
  Future<ReloadReport> reloadSources(String isolateId,
      {bool force, bool pause, String rootLibUri, String packagesUri}) {
    throw UnimplementedError();
  }

  @override
  Future<Success> removeBreakpoint(String isolateId, String breakpointId) {
    throw UnimplementedError();
  }

  @override
  Future<Success> requestHeapSnapshot(
      String isolateId, String roots, bool collectGarbage) {
    throw UnimplementedError();
  }

  @override
  Future<Success> resume(String isolateId, {String step, int frameIndex}) {
    throw UnimplementedError();
  }

  @override
  Future<Success> setExceptionPauseMode(String isolateId, String mode) {
    throw UnimplementedError();
  }

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
      chromeConsoleSubscription =
          _tabConnection.runtime.onConsoleAPICalled.listen((e) {
        if (!filter(e)) return;
        var args = e.params['args'] as List;
        var item = args[0] as Map;
        var value = '${item["value"]}\n';
        controller.add(Event()
          ..kind = EventKind.kWriteEvent
          ..isolate = toIsolateRef(_isolate)
          ..bytes = base64.encode(value.codeUnits)
          ..timestamp = e.timestamp.toInt());
      });
      if (includeExceptions) {
        exceptionsSubscription =
            _tabConnection.runtime.onExceptionThrown.listen((e) {
          controller.add(Event()
            ..kind = EventKind.kWriteEvent
            ..isolate = toIsolateRef(_isolate)
            ..bytes = base64
                .encode(e.exceptionDetails.exception.description.codeUnits));
        });
      }
    });
    return controller;
  }

  /// Listens to the `debugger` events from chrome and translates those to
  /// the `Debug` stream events for the vm service protocol.
  ///
  /// TODO: Implement the rest https://github.com/dart-lang/webdev/issues/166
  StreamController<Event> _debugStreamController() {
    StreamSubscription pauseSubscription;
    StreamSubscription resumeSubscription;
    return StreamController<Event>.broadcast(onListen: () {
      pauseSubscription = _tabConnection.debugger.onPaused.listen((e) async {
        var event = Event()..isolate = toIsolateRef(_isolate);
        var params = e.params;
        var breakpoints = params['hitBreakpoints'] as List;
        if (breakpoints.isNotEmpty) {
          // TODO: Set `breakpoint` and `pauseBreakpoints` fields.
          event.kind = EventKind.kPauseBreakpoint;
        } else if (e.reason == 'exception' || e.reason == 'assert') {
          event.kind = EventKind.kPauseException;
        } else {
          event.kind = EventKind.kPauseInterrupted;
        }
        _streamNotify('Debug', event);
      });
      resumeSubscription = _tabConnection.debugger.onResumed.listen((e) async {
        _streamNotify(
            'Debug',
            Event()
              ..kind = EventKind.kResume
              ..isolate = toIsolateRef(_isolate));
      });
    }, onCancel: () {
      pauseSubscription.cancel();
      resumeSubscription.cancel();
    });
  }

  /// Adds [event] to the stream with [streamId] if there is anybody listening
  /// on that stream.
  void _streamNotify(String streamId, Event event) {
    var controller = _streamControllers[streamId];
    if (controller == null) return;
    controller.add(event);
  }
}

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stderr` logs.
const _stderrTypes = ['error'];

/// The `type`s of [ConsoleAPIEvent]s that are treated as `stdout` logs.
const _stdoutTypes = ['log', 'info', 'warning'];
