// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'helpers.dart';

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService implements VmServiceInterface {
  /// The root connection with a chrome instance.
  // ignore: unused_field
  final ChromeConnection _chromeConnection;

  /// All current isolates by their id.
  final Map<String, Isolate> _isolates;

  /// Maps isolates by id to their underlying [WipConnection].
  // ignore: unused_field
  final Map<String, WipConnection> _isolateConnections;

  /// The root `VM` instance. There can only be one of these, but its isolates
  /// are dynamic and roughly map to chrome tabs.
  final VM _vm;

  ChromeProxyService._(this._chromeConnection, this._vm, this._isolates,
      this._isolateConnections);

  static Future<ChromeProxyService> create(
      ChromeConnection chromeConnection) async {
    // TODO: Robust isolate handling: https://github.com/dart-lang/webdev/issues/151

    // Find the Chrome tabs that look like dart apps.
    var tabs = (await chromeConnection.getTabs()).where((ChromeTab tab) {
      return !tab.isBackgroundPage &&
          !tab.isChromeExtension &&
          !tab.url.startsWith('chrome-devtools://');
    });

    var isolates = <String, Isolate>{};
    var isolateRefs = <IsolateRef>[];
    var isolateConnections = <String, WipConnection>{};
    for (var tab in tabs) {
      var id = createId();
      var isolate = Isolate()
        ..id = id
        ..number = id
        ..name = '${tab.url}:main()'
        ..runnable = true
        ..breakpoints = [];
      var isolateRef = toIsolateRef(isolate);
      isolate.pauseEvent = Event()
        ..kind = EventKind.kResume
        ..isolate = isolateRef;

      isolateRefs.add(isolateRef);
      isolates[id] = isolate;
      var tabConnection = await tab.connect();
      isolateConnections[isolate.id] = tabConnection;

      await tabConnection.runtime.enable();
    }

    // TODO: What about `architectureBits`, `targetCPU`, `hostCPU` and `pid`?
    final vm = VM()
      ..isolates = isolateRefs
      ..name = 'ChromeDebugProxy'
      ..startTime = DateTime.now().millisecondsSinceEpoch
      ..version = Platform.version;

    return ChromeProxyService._(
        chromeConnection, vm, isolates, isolateConnections);
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

  @override
  Future getIsolate(String isolateId) async {
    var isolate = _isolates[isolateId];
    if (isolate == null) {
      throw ArgumentError.value(
          isolateId, 'isolateId', 'Unrecognized isolate id');
    }
    return isolate;
  }

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
    throw UnimplementedError();
  }

  @override
  Future<Success> pause(String isolateId) {
    throw UnimplementedError();
  }

  @override
  Future<Success> registerService(String service, String alias) {
    throw UnimplementedError();
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
  Future<Success> setName(String isolateId, String name) {
    throw UnimplementedError();
  }

  @override
  Future<Success> setVMName(String name) {
    throw UnimplementedError();
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
  Future<Success> streamListen(String streamId) {
    throw UnimplementedError();
  }
}
