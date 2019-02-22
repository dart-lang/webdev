// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
@TestOn('vm')
import 'dart:io';

import 'package:test/test.dart';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webdev/src/serve/chrome.dart';

import 'package:dwds/src/chrome_proxy_service.dart';

void main() {
  Chrome chrome;
  ChromeProxyService service;

  setUpAll(() async {
    chrome = await Chrome.start(['https://www.google.com/']);
    var connection = chrome.chromeConnection;
    service =
        await ChromeProxyService.create(connection, 'https://www.google.com/');
  });

  tearDownAll(() async {
    await chrome.close();
  });

  test('addBreakPoint', () {
    expect(() => service.addBreakpoint(null, null, null),
        throwsUnimplementedError);
  });

  test('addBreakpointAtEntry', () {
    expect(() => service.addBreakpointAtEntry(null, null),
        throwsUnimplementedError);
  });

  test('addBreakpointWithScriptUri', () {
    expect(() => service.addBreakpointWithScriptUri(null, null, null),
        throwsUnimplementedError);
  });

  test('clearCpuProfile', () {
    expect(() => service.clearCpuProfile(null), throwsUnimplementedError);
  });

  test('clearVMTimeline', () {
    expect(() => service.clearVMTimeline(), throwsUnimplementedError);
  });

  test('addBreakPoint', () {
    expect(() => service.addBreakpoint(null, null, null),
        throwsUnimplementedError);
  });

  test('clearVMTimeline', () {
    expect(() => service.clearVMTimeline(), throwsUnimplementedError);
  });

  test('collectAllGarbage', () {
    expect(() => service.collectAllGarbage(null), throwsUnimplementedError);
  });

  test('clearVMTimeline', () {
    expect(() => service.clearVMTimeline(), throwsUnimplementedError);
  });

  test('evaluate', () {
    expect(() => service.evaluate(null, null, null), throwsUnimplementedError);
  });

  test('evaluateInFrame', () {
    expect(() => service.evaluateInFrame(null, null, null),
        throwsUnimplementedError);
  });

  test('getAllocationProfile', () {
    expect(() => service.getAllocationProfile(null), throwsUnimplementedError);
  });

  test('getCpuProfile', () {
    expect(() => service.getCpuProfile(null, null), throwsUnimplementedError);
  });

  test('getFlagList', () {
    expect(() => service.getFlagList(), throwsUnimplementedError);
  });

  test('getInstances', () {
    expect(
        () => service.getInstances(null, null, null), throwsUnimplementedError);
  });

  group('getIsolate', () {
    test('works for existing isolates', () async {
      var vm = await service.getVM();
      var result = await service.getIsolate(vm.isolates.first.id);
      expect(result, const TypeMatcher<Isolate>());
      var isolate = result as Isolate;
      expect(isolate.name, contains('google.com'));
    });

    test('throws for invalid ids', () async {
      expect(service.getIsolate('bad'), throwsArgumentError);
    });
  });

  test('getObject', () {
    expect(() => service.getObject(null, null), throwsUnimplementedError);
  });

  test('getScripts', () {
    expect(() => service.getScripts(null), throwsUnimplementedError);
  });

  test('clearVMTimeline', () {
    expect(() => service.clearVMTimeline(), throwsUnimplementedError);
  });

  test('getSourceReport', () {
    expect(() => service.getSourceReport(null, null), throwsUnimplementedError);
  });

  test('getStack', () {
    expect(() => service.getStack(null), throwsUnimplementedError);
  });

  test('getVM', () async {
    var vm = await service.getVM();
    expect(vm.name, isNotNull);
    expect(vm.version, Platform.version);
    expect(vm.isolates.length, equals(1));
    var isolate = vm.isolates.first;
    expect(isolate.id, isNotNull);
    expect(isolate.name, isNotNull);
    expect(isolate.number, isNotNull);
  });

  test('getVersion', () {
    expect(() => service.getVersion(), throwsUnimplementedError);
  });

  test('invoke', () {
    expect(
        () => service.invoke(null, null, null, null), throwsUnimplementedError);
  });

  test('kill', () {
    expect(() => service.kill(null), throwsUnimplementedError);
  });

  test('onEvent', () {
    expect(() => service.onEvent(null), throwsUnimplementedError);
  });

  test('pause', () {
    expect(() => service.pause(null), throwsUnimplementedError);
  });

  test('registerService', () {
    expect(() => service.registerService(null, null), throwsUnimplementedError);
  });

  test('reloadSources', () {
    expect(() => service.reloadSources(null), throwsUnimplementedError);
  });

  test('removeBreakpoint', () {
    expect(
        () => service.removeBreakpoint(null, null), throwsUnimplementedError);
  });

  test('requestHeapSnapshot', () {
    expect(() => service.requestHeapSnapshot(null, null, null),
        throwsUnimplementedError);
  });

  test('resume', () {
    expect(() => service.resume(null), throwsUnimplementedError);
  });

  test('setExceptionPauseMode', () {
    expect(() => service.setExceptionPauseMode(null, null),
        throwsUnimplementedError);
  });

  test('setFlag', () {
    expect(() => service.setFlag(null, null), throwsUnimplementedError);
  });

  test('setLibraryDebuggable', () {
    expect(() => service.setLibraryDebuggable(null, null, null),
        throwsUnimplementedError);
  });

  test('setName', () {
    expect(() => service.setName(null, null), throwsUnimplementedError);
  });

  test('setVMName', () {
    expect(() => service.setVMName(null), throwsUnimplementedError);
  });

  test('setVMTimelineFlags', () {
    expect(() => service.setVMTimelineFlags(null), throwsUnimplementedError);
  });

  test('streamCancel', () {
    expect(() => service.streamCancel(null), throwsUnimplementedError);
  });

  test('streamListen', () {
    expect(() => service.streamListen(null), throwsUnimplementedError);
  });
}
