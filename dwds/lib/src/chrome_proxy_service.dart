// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// A proxy from the chrome debug protocol to the dart vm service protocol.
class ChromeProxyService implements VmServiceInterface {
  // ignore: unused_field
  final ChromeConnection _chromeConnection;

  ChromeProxyService(this._chromeConnection);

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
  Future getIsolate(String isolateId) {
    throw UnimplementedError();
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
  Future<VM> getVM() {
    throw UnimplementedError();
  }

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
