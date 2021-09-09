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
import 'fixtures/logging.dart';

ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);

WipConnection get tabConnection => context.tabConnection;

final context = TestContext();

void main() {
  Future initialEvents;

  setUpAll(() async {
    setCurrentLogWriter();
    initialEvents = expectLater(
        eventStream,
        emitsThrough(predicate((DwdsEvent event) =>
            event.type == DwdsEventKind.compilerUpdateDependencies &&
            event.payload['elapsedMilliseconds'] != null)));
    await context.setUp(
      serveDevTools: true,
      enableExpressionEvaluation: true,
    );
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  test('emits DEVTOOLS_LAUNCH event', () async {
    // The events stream is a broadcast stream so start listening before the
    // action.
    var events = expectLater(
        context.testServer.dwds.events,
        emitsThrough(predicate(
            (DwdsEvent event) => event.type == DwdsEventKind.devtoolsLaunch)));
    await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
    await events;
  });

  test('emits DEBUGGER_READY event', () async {
    // The events stream is a broadcast stream so start listening before the
    // action.
    var events = expectLater(
        context.testServer.dwds.events,
        emitsThrough(predicate(
            (DwdsEvent event) => event.type == DwdsEventKind.debuggerReady)));
    await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
    await events;
  },
      skip:
          'https://github.com/dart-lang/webdev/issues/1406'); // Not implemented yet.

  test('events can be listened to multiple times', () async {
    context.testServer.dwds.events.listen((_) {});
    context.testServer.dwds.events.listen((_) {});
  });

  test('can emit event through service extension', () async {
    var events = expectLater(
        context.testServer.dwds.events,
        emitsThrough(predicate((DwdsEvent event) =>
            event.type == 'foo-event' && event.payload['data'] == 1234)));

    var response = await context.debugConnection.vmService
        .callServiceExtension('ext.dwds.emitEvent', args: {
      'type': 'foo-event',
      'payload': {'data': 1234},
    });
    expect(response.type, 'Success');
    await events;
  });

  test('can receive DevtoolsEvent and emit DEBUGGER_READY event', () async {
    var events = expectLater(
        context.testServer.dwds.events,
        emitsThrough(predicate((DwdsEvent event) =>
            event.type == DwdsEventKind.debuggerReady &&
            event.payload['elapsedMilliseconds'] != null)));

    var response = await context.debugConnection.vmService
        .callServiceExtension('ext.dwds.sendEvent', args: {
      'type': 'DevtoolsEvent',
      'payload': {'screen': 'debugger'},
    });
    expect(response.type, 'Success');
    await events;
  });

  group('evaluate', () {
    Isolate isolate;
    LibraryRef bootstrap;

    setUpAll(() async {
      setCurrentLogWriter();
      var vm = await service.getVM();
      isolate = await service.getIsolate(vm.isolates.first.id);
      bootstrap = isolate.rootLib;
    });

    setUp(() async {
      setCurrentLogWriter();
    });

    test('emits EVALUATE events on evaluation success', () async {
      var expression = "helloString('world')";
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.evaluate &&
              event.payload['expression'] == expression &&
              event.payload['success'] == true &&
              event.payload['error'] == null &&
              event.payload['exception'] == null &&
              event.payload['elapsedMilliseconds'] != null)));
      await service.evaluate(
        isolate.id,
        bootstrap.id,
        expression,
      );
      await events;
    });

    test('emits COMPILER_UPDATE_DEPENDENCIES event', () async {
      await initialEvents;
    });

    test('emits EVALUATE events on evaluation failure', () async {
      var expression = 'some-bad-expression';
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.evaluate &&
              event.payload['expression'] == expression &&
              event.payload['success'] == false &&
              event.payload['error'] is ErrorRef &&
              event.payload['exception'] == null &&
              event.payload['elapsedMilliseconds'] != null)));
      await service.evaluate(
        isolate.id,
        bootstrap.id,
        expression,
      );
      await events;
    });
  });

  group('evaluateInFrame', () {
    String isolateId;
    Stream<Event> stream;
    ScriptList scripts;
    ScriptRef mainScript;

    setUpAll(() async {
      setCurrentLogWriter();
      var vm = await service.getVM();

      isolateId = vm.isolates.first.id;
      scripts = await service.getScripts(isolateId);
      await service.streamListen('Debug');
      stream = service.onEvent('Debug');
      mainScript = scripts.scripts
          .firstWhere((script) => script.uri.contains('main.dart'));
    });

    setUp(() async {
      setCurrentLogWriter();
    });

    test('emits EVALUATE_IN_FRAME events on RPC error', () async {
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.evaluateInFrame &&
              event.payload['success'] == false &&
              event.payload['error'] == null &&
              event.payload['elapsedMilliseconds'] != null &&
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
      await events;
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
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.evaluateInFrame &&
              event.payload['success'] == false &&
              event.payload['error'] is ErrorRef &&
              event.payload['exception'] == null &&
              event.payload['elapsedMilliseconds'] != null)));
      try {
        await service.evaluateInFrame(
          isolateId,
          0,
          'some-bad-expression',
        );
      } catch (_) {
      } finally {
        await events;
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
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.evaluateInFrame &&
              event.payload['success'] == true &&
              event.payload['error'] == null &&
              event.payload['exception'] == null &&
              event.payload['elapsedMilliseconds'] != null)));
      try {
        await service.evaluateInFrame(
          isolateId,
          0,
          'true',
        );
      } catch (_) {
      } finally {
        await events;
        await service.removeBreakpoint(isolateId, bp.id);
        await service.resume(isolateId);
      }
    });
  });

  group('getSourceReport', () {
    String isolateId;
    ScriptList scripts;
    ScriptRef mainScript;

    setUp(() async {
      setCurrentLogWriter();
      var vm = await service.getVM();
      isolateId = vm.isolates.first.id;
      scripts = await service.getScripts(isolateId);

      mainScript = scripts.scripts
          .firstWhere((script) => script.uri.contains('main.dart'));
    });

    test('emits GET_SOURCE_REPORT events', () async {
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(
            predicate((DwdsEvent event) =>
                event.type == DwdsEventKind.getSourceReport &&
                event.payload['elapsedMilliseconds'] != null),
          ));
      await service.getSourceReport(
          isolateId, [SourceReportKind.kPossibleBreakpoints],
          scriptId: mainScript.id);
      await events;
    });
  });

  group('getSripts', () {
    String isolateId;

    setUp(() async {
      setCurrentLogWriter();
      var vm = await service.getVM();
      isolateId = vm.isolates.first.id;
    });

    test('emits GET_SCRIPTS events', () async {
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.getScripts &&
              event.payload['elapsedMilliseconds'] != null)));
      await service.getScripts(isolateId);
      await events;
    });
  });

  group('getIsolate', () {
    String isolateId;

    setUp(() async {
      setCurrentLogWriter();
      var vm = await service.getVM();
      isolateId = vm.isolates.first.id;
    });

    test('emits GET_ISOLATE events', () async {
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.getIsolate &&
              event.payload['elapsedMilliseconds'] != null)));
      await service.getIsolate(isolateId);
      await events;
    });
  });

  group('getVM', () {
    setUp(() async {
      setCurrentLogWriter();
    });

    test('emits GET_VM events', () async {
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.getVM &&
              event.payload['elapsedMilliseconds'] != null)));
      await service.getVM();
      await events;
    });
  });

  group('resume', () {
    String isolateId;
    Stream<Event> stream;
    ScriptList scripts;
    ScriptRef mainScript;

    setUp(() async {
      setCurrentLogWriter();
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
      var events = expectLater(
          context.testServer.dwds.events,
          emitsThrough(predicate((DwdsEvent event) =>
              event.type == DwdsEventKind.resume &&
              event.payload['elapsedMilliseconds'] != null)));
      await service.resume(isolateId, step: 'Into');
      await events;
    });
  });
}
