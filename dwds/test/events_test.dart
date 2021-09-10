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

  Matcher matchesEvent(String type, Map<String, Object> payload) {
    return isA<DwdsEvent>()
        .having((e) => e.type, 'type', type)
        .having((e) => e.payload.keys, 'payload.keys', payload.keys)
        .having((e) => e.payload.values, 'payload.values', payload.values);
  }

  Stream<DwdsEvent> pipe(Stream<DwdsEvent> stream, {Timeout timeout}) {
    var controller = StreamController<DwdsEvent>();
    unawaited(stream
        .forEach(controller.add)
        .timeout(timeout?.duration ?? const Duration(seconds: 20))
        .catchError((_) {})
        .then((value) => controller.close()));
    return controller.stream;
  }

  setUpAll(() async {
    setCurrentLogWriter();
    initialEvents = expectLater(
        pipe(eventStream, timeout: const Timeout.factor(5)),
        emitsThrough(matchesEvent(DwdsEventKind.compilerUpdateDependencies, {
          'entrypoint': 'hello_world/main.dart.bootstrap.js',
          'elapsedMilliseconds': isNotNull
        })));
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
    var events = expectLater(pipe(context.testServer.dwds.events),
        emitsThrough(matchesEvent(DwdsEventKind.devtoolsLaunch, {})));
    await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
    await events;
  });

  test('emits DEBUGGER_READY event', () async {
    // The events stream is a broadcast stream so start listening before the
    // action.
    var events = expectLater(pipe(context.testServer.dwds.events),
        emitsThrough(matchesEvent(DwdsEventKind.debuggerReady, {})));
    await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
    await events;
  }, skip: 'https://github.com/dart-lang/webdev/issues/1406');

  test('events can be listened to multiple times', () async {
    context.testServer.dwds.events.listen((_) {});
    context.testServer.dwds.events.listen((_) {});
  });

  test('can emit event through service extension', () async {
    var events = expectLater(pipe(context.testServer.dwds.events),
        emitsThrough(matchesEvent('foo-event', {'data': 1234})));
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
        pipe(context.testServer.dwds.events),
        emitsThrough(matchesEvent(DwdsEventKind.debuggerReady, {
          'elapsedMilliseconds': isNotNull,
        })));
    var response = await context.debugConnection.vmService
        .callServiceExtension('ext.dwds.sendEvent', args: {
      'type': 'DevtoolsEvent',
      'payload': {'screen': 'debugger', 'action': 'screenReady'},
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.evaluate, {
            'expression': expression,
            'success': isTrue,
            'elapsedMilliseconds': isNotNull,
          })));
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.evaluate, {
            'expression': expression,
            'success': isFalse,
            'error': isA<ErrorRef>(),
            'elapsedMilliseconds': isNotNull,
          })));
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
      var expression = 'some-bad-expression';
      var events = expectLater(
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.evaluateInFrame, {
            'expression': expression,
            'success': isFalse,
            'exception': isA<RPCError>().having(
                (e) => e.message, 'message', contains('program is not paused')),
            'elapsedMilliseconds': isNotNull,
          })));
      try {
        await service.evaluateInFrame(
          isolateId,
          0,
          expression,
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
      var expression = 'some-bad-expression';
      var events = expectLater(
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.evaluateInFrame, {
            'expression': expression,
            'success': isFalse,
            'error': isA<ErrorRef>(),
            'elapsedMilliseconds': isNotNull,
          })));
      try {
        await service.evaluateInFrame(
          isolateId,
          0,
          expression,
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.evaluateInFrame, {
            'expression': 'true',
            'success': isTrue,
            'elapsedMilliseconds': isNotNull,
          })));
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.getSourceReport, {
            'elapsedMilliseconds': isNotNull,
          })));
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.getScripts, {
            'elapsedMilliseconds': isNotNull,
          })));
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.getIsolate, {
            'elapsedMilliseconds': isNotNull,
          })));
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.getVM, {
            'elapsedMilliseconds': isNotNull,
          })));
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
          pipe(context.testServer.dwds.events),
          emitsThrough(matchesEvent(DwdsEventKind.resume, {
            'step': 'Into',
            'elapsedMilliseconds': isNotNull,
          })));
      await service.resume(isolateId, step: 'Into');
      await events;
    });
  });
}
