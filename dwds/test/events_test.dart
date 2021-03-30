// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webdriver/async_core.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);

WipConnection get tabConnection => context.tabConnection;

final context = TestContext();

void main() {
  setUpAll(() async {
    await context.setUp(
      serveDevTools: true,
      enableExpressionEvaluation: true,
    );
  });

  test('emits DEVTOOLS_LAUNCH event', () async {
    // The events stream is a broadcast stream so start listening before the
    // action.
    expect(context.testServer.dwds.events,
        emits(predicate((DwdsEvent event) => event.type == 'DEVTOOLS_LAUNCH')));
    await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
  });

  test('emits COMPILER_UPDATE_DEPENDENCIES event', () async {
    // The events stream is a broadcast stream so start listening before the
    // action.
    expect(
        context.testServer.dwds.events,
        emits(predicate((DwdsEvent event) =>
            event.type == 'COMPILER_UPDATE_DEPENDENCIES')));
  });

  test('events can be listened to multiple times', () async {
    context.testServer.dwds.events.listen((_) {});
    context.testServer.dwds.events.listen((_) {});
  });

  group('evaluate', () {
    Isolate isolate;
    LibraryRef bootstrap;

    setUpAll(() async {
      var vm = await service.getVM();
      isolate = await service.getIsolate(vm.isolates.first.id);
      bootstrap = isolate.rootLib;
    });

    test('emits EVALUATE events on evaluation success', () async {
      var expression = "helloString('world')";
      expect(
          context.testServer.dwds.events,
          emits(predicate((DwdsEvent event) =>
              event.type == 'EVALUATE' &&
              event.payload['expression'] == expression)));
      await service.evaluate(
        isolate.id,
        bootstrap.id,
        expression,
      );
    });

    test('emits EVALUATE events on evaluation failure', () async {
      var expression = 'some-bad-expression';
      expect(
          context.testServer.dwds.events,
          emits(predicate((DwdsEvent event) =>
              event.type == 'EVALUATE' &&
              event.payload['expression'] == expression &&
              event.payload['exception'] is ErrorRef)));
      await service.evaluate(
        isolate.id,
        bootstrap.id,
        expression,
      );
    });
  });

  group('evaluateInFrame', () {
    String isolateId;
    Stream<Event> stream;
    ScriptList scripts;
    ScriptRef mainScript;

    setUpAll(() async {
      var vm = await service.getVM();

      isolateId = vm.isolates.first.id;
      scripts = await service.getScripts(isolateId);
      await service.streamListen('Debug');
      stream = service.onEvent('Debug');
      mainScript = scripts.scripts
          .firstWhere((script) => script.uri.contains('main.dart'));
    });
    test('emits EVALUATE_IN_FRAME events on RPC error', () async {
      expect(
          context.testServer.dwds.events,
          emits(predicate((DwdsEvent event) =>
              event.type == 'EVALUATE_IN_FRAME' &&
              event.payload['success'] == false &&
              event.payload['exception'] is RPCError &&
              (event.payload['exception'] as RPCError)
                  .message
                  .contains('program is not paused'))));
      try {
        await service.evaluateInFrame(
          isolateId,
          0,
          'some-bad-expression',
        );
      } catch (_) {}
    });

    test('emits EVALUATE_IN_FRAME events on evaluation error', () async {
      var line = await context.findBreakpointLine(
          'callPrintCount', isolateId, mainScript);
      var bp = await service.addBreakpoint(isolateId, mainScript.id, line);
      // Wait for breakpoint to trigger.
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

      // Evaluation succeeds and return ErrorRef containing compilation error,
      // so event is marked as success.
      expect(
          context.testServer.dwds.events,
          emits(predicate((DwdsEvent event) =>
              event.type == 'EVALUATE_IN_FRAME' &&
              event.payload['success'] == false &&
              event.payload['exception'] is ErrorRef)));
      try {
        await service.evaluateInFrame(
          isolateId,
          0,
          'some-bad-expression',
        );
      } catch (_) {} finally {
        await service.removeBreakpoint(isolateId, bp.id);
        await service.resume(isolateId);
      }
    });

    test('emits EVALUATE_IN_FRAME events on evaluation success', () async {
      var line = await context.findBreakpointLine(
          'callPrintCount', isolateId, mainScript);
      var bp = await service.addBreakpoint(isolateId, mainScript.id, line);
      // Wait for breakpoint to trigger.
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

      // Evaluation succeeds and return InstanceRef,
      // so event is marked as success.
      expect(
          context.testServer.dwds.events,
          emits(predicate((DwdsEvent event) =>
              event.type == 'EVALUATE_IN_FRAME' &&
              event.payload['success'] == true)));
      try {
        await service.evaluateInFrame(
          isolateId,
          0,
          'true',
        );
      } catch (_) {} finally {
        await service.removeBreakpoint(isolateId, bp.id);
        await service.resume(isolateId);
      }
    });
  });

  group('resume', () {
    String isolateId;
    Stream<Event> stream;
    ScriptList scripts;
    ScriptRef mainScript;

    setUp(() async {
      var vm = await service.getVM();
      isolateId = vm.isolates.first.id;
      scripts = await service.getScripts(isolateId);
      await service.streamListen('Debug');
      stream = service.onEvent('Debug');
      mainScript = scripts.scripts
          .firstWhere((script) => script.uri.contains('main.dart'));
      var line = await context.findBreakpointLine(
          'callPrintCount', isolateId, mainScript);
      var bp = await service.addBreakpoint(isolateId, mainScript.id, line);
      // Wait for breakpoint to trigger.
      await stream
          .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);
      await service.removeBreakpoint(isolateId, bp.id);
    });

    tearDown(() async {
      // Resume execution to not impact other tests.
      await service.resume(isolateId);
    });

    test('emits RESUME events', () async {
      expect(context.testServer.dwds.events,
          emits(predicate((DwdsEvent event) => event.type == 'RESUME')));
      await service.resume(isolateId, step: 'Into');
    });
  });
}
