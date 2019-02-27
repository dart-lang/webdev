// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webdev/src/serve/chrome.dart';
import 'package:webdev/src/serve/utils.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'package:dwds/src/chrome_proxy_service.dart';

void main() {
  String appUrl;
  Chrome chrome;
  ChromeProxyService service;
  WipConnection tabConnection;
  Process webdev;

  setUpAll(() async {
    var port = await findUnusedPort();
    webdev = await Process.start(
        'pub', ['global', 'run', 'webdev', 'serve', 'example:$port']);
    webdev.stderr
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen(print);
    await webdev.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .takeWhile((line) => !line.contains('$port'))
        .map((line) {
      print(line);
      return line;
    }).drain();
    appUrl = 'http://localhost:$port/hello_world/';
    chrome = await Chrome.start([appUrl]);
    var connection = chrome.chromeConnection;
    var tab = await connection.getTab((t) => t.url == appUrl);
    tabConnection = await tab.connect();
    await tabConnection.runtime.enable();

    // Check if the app is already loaded, look for the top level
    // `registerExtension` variable which we set as the last step.
    var result = await tabConnection.runtime
        .evaluate('(window.registerExtension !== undefined).toString();');
    if (result.value != 'true') {
      // If it wasn't already loaded, then wait for the 'Page Ready' log.
      await tabConnection.runtime.onConsoleAPICalled.firstWhere((event) =>
          event.type == 'debug' && event.args[0].value == 'Page Ready');
    }

    service = await ChromeProxyService.create(connection, appUrl);
  });

  tearDownAll(() async {
    webdev.kill();
    await webdev.exitCode;
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
      expect(isolate.name, contains(appUrl));
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

  test('registerService', () async {
    expect(service.registerService('ext.foo.bar', null), completion(isSuccess));
    var vm = await service.getVM();
    var isolate = await service.getIsolate(vm.isolates.first.id) as Isolate;
    expect(isolate.extensionRPCs, contains('ext.foo.bar'));
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

  test('setName', () async {
    var vm = await service.getVM();
    var isolateId = vm.isolates.first.id;
    expect(service.setName(isolateId, 'test'), completion(isSuccess));
    var isolate = await service.getIsolate(isolateId);
    expect(isolate.name, 'test');
  });

  test('setVMName', () async {
    expect(service.setVMName('foo'), completion(isSuccess));
    var vm = await service.getVM();
    expect(vm.name, 'foo');
  });

  test('setVMTimelineFlags', () {
    expect(() => service.setVMTimelineFlags(null), throwsUnimplementedError);
  });

  test('streamCancel', () {
    expect(() => service.streamCancel(null), throwsUnimplementedError);
  });

  group('streamListen/onEvent', () {
    test('Debug', () async {
      expect(() => service.streamListen('Debug'), throwsUnimplementedError);
    });

    test('Extension', () async {
      expect(service.streamListen('Extension'), completion(isSuccess));
      var stream = service.onEvent('Extension');
      var eventKind = 'my.custom.event';
      expect(
          stream,
          emitsThrough(predicate((Event event) =>
              event.kind == EventKind.kExtension &&
              event.extensionKind == eventKind &&
              event.extensionData.data['example'] == 'data')));
      await tabConnection.runtime.evaluate("postEvent('$eventKind');");
    });

    test('GC', () async {
      expect(() => service.streamListen('GC'), throwsUnimplementedError);
    });

    test('Isolate', () async {
      expect(service.streamListen('Isolate'), completion(isSuccess));
      var stream = service.onEvent('Isolate');
      var extensionMethod = 'ext.foo.bar';
      expect(
          stream,
          emitsThrough(predicate((Event event) =>
              event.kind == EventKind.kServiceExtensionAdded &&
              event.extensionRPC == extensionMethod)));
      await tabConnection.runtime
          .evaluate("registerExtension('$extensionMethod');");
    });

    test('Timeline', () async {
      expect(() => service.streamListen('Timeline'), throwsUnimplementedError);
    });

    test('Stdout', () async {
      expect(service.streamListen('Stdout'), completion(isSuccess));
      expect(
          service.onEvent('Stdout'),
          emitsThrough(predicate((Event event) =>
              event.kind == EventKind.kWriteEvent &&
              String.fromCharCodes(base64.decode(event.bytes))
                  .contains('hello'))));
      await tabConnection.runtime.evaluate('console.log("hello");');
    });

    test('Stderr', () async {
      expect(service.streamListen('Stderr'), completion(isSuccess));
      var stderrStream = service.onEvent('Stderr');
      expect(
          stderrStream,
          emitsThrough(predicate((Event event) =>
              event.kind == EventKind.kWriteEvent &&
              String.fromCharCodes(base64.decode(event.bytes))
                  .contains('Error'))));
      await tabConnection.runtime.evaluate('console.error("Error");');
    });

    test('VM', () async {
      var status = await service.streamListen('VM');
      expect(status, isSuccess);
      var stream = service.onEvent('VM');
      expect(
          stream,
          emitsThrough(predicate((Event e) =>
              e.kind == EventKind.kVMUpdate && e.vm.name == 'test')));
      await service.setVMName('test');
    });

    test('_Service', () async {
      expect(service.streamListen('_Service'), completion(isSuccess));
      var stream = service.onEvent('_Service');
      var extensionMethod = 'ext.foo.bar';
      expect(
          stream,
          emitsThrough(predicate((Event event) =>
              event.kind == EventKind.kServiceRegistered &&
              event.extensionRPC == extensionMethod)));
      await service.registerService(extensionMethod, null);
    });
  });
}

const isSuccess = TypeMatcher<Success>();
