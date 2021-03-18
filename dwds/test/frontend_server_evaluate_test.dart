// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@TestOn('vm')
import 'dart:async';

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';
import 'fixtures/logging.dart';

class TestSetup {
  static final contextUnsound = TestContext(
      directory: p.join('..', 'fixtures', '_testPackage'),
      entry: p.join('..', 'fixtures', '_testPackage', 'web', 'main.dart'),
      path: 'index.html',
      pathToServe: 'web');

  TestContext context;

  TestSetup.unsound() : context = contextUnsound;

  ChromeProxyService get service =>
      fetchChromeProxyService(context.debugConnection);
  WipConnection get tabConnection => context.tabConnection;
}

void main() async {
  var setup = TestSetup.unsound();
  var context = setup.context;

  Future<void> onBreakPoint(String isolate, ScriptRef script,
      String breakPointId, Future<void> Function() body) async {
    Breakpoint bp;
    try {
      var line =
          await context.findBreakpointLine(breakPointId, isolate, script);
      bp = await setup.service
          .addBreakpointWithScriptUri(isolate, script.uri, line);
      await body();
    } finally {
      // Remove breakpoint so it doesn't impact other tests or retries.
      if (bp != null) {
        await setup.service.removeBreakpoint(isolate, bp.id);
      }
    }
  }

  group('shared context with evaluation', () {
    setUpAll(() async {
      // Note: change 'printOnFailure' to 'print' for debug printing
      configureLogWriter(
          customLogWriter: (level, message,
                  {loggerName, error, stackTrace, verbose}) =>
              printOnFailure('[$level] $loggerName: $message'));

      await context.setUp(
          enableExpressionEvaluation: true,
          compilationMode: CompilationMode.frontendServer,
          verbose: false);
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('evaluateInFrame', () {
      VM vm;
      Isolate isolate;
      ScriptList scripts;
      ScriptRef mainScript;
      Stream<Event> stream;

      setUp(() async {
        vm = await setup.service.getVM();
        isolate = await setup.service.getIsolate(vm.isolates.first.id);
        scripts = await setup.service.getScripts(isolate.id);

        await setup.service.streamListen('Debug');
        stream = setup.service.onEvent('Debug');

        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      tearDown(() async {
        await setup.service.resume(isolate.id);
      });

      test('local', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await setup.service
              .evaluateInFrame(isolate.id, event.topFrame.index, 'local');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('global', () async {
        await onBreakPoint(isolate.id, mainScript, 'printGlobal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await setup.service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'testLibraryValue');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '3'));
        });
      });

      test('call core function', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await setup.service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'print(local)');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString,
                  'valueAsString',
                  'null'));
        });
      });

      test('call library function with const param', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await setup.service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'testLibraryFunction(42)');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('call library function with local param', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await setup.service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'testLibraryFunction(local)');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('loop variable', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLoopVariable',
            () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await setup.service
              .evaluateInFrame(isolate.id, event.topFrame.index, 'item');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('error', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var error = await setup.service
              .evaluateInFrame(isolate.id, event.topFrame.index, 'typo');

          expect(
              error,
              const TypeMatcher<ErrorRef>().having(
                  (instance) => instance.message,
                  'message',
                  'CompilationError: Getter not found: \'typo\'.\ntypo\n^^^^'));
        });
      });
    });

    group('evaluate', () {
      VM vm;
      Isolate isolate;

      setUp(() async {
        vm = await setup.service.getVM();
        isolate = await setup.service.getIsolate(vm.isolates.first.id);

        await setup.service.streamListen('Debug');
      });

      tearDown(() async {});

      test('uses symbol from the same library', () async {
        var library = isolate.libraries.first;
        var result = await setup.service
            .evaluate(isolate.id, library.id, 'MainClass(0).toString()');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '0'));
      });

      test('uses symbol from another library', () async {
        var library = isolate.libraries.first;
        var result = await setup.service.evaluate(
            isolate.id, library.id, 'TestLibraryClass(0,1).toString()');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString,
                'valueAsString',
                'field: 0, _field: 1'));
      });

      test('closure call', () async {
        var library = isolate.libraries.first;
        var result = await setup.service
            .evaluate(isolate.id, library.id, '(() => 42)()');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '42'));
      });
    }, tags: ['unreleased-sdk']);
  });

  group('shared context with no evaluation', () {
    setUpAll(() async {
      await context.setUp(
          enableExpressionEvaluation: false,
          compilationMode: CompilationMode.frontendServer,
          verbose: false);
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('evaluateInFrame', () {
      VM vm;
      Isolate isolate;
      ScriptList scripts;
      ScriptRef mainScript;
      Stream<Event> stream;

      setUp(() async {
        vm = await setup.service.getVM();
        isolate = await setup.service.getIsolate(vm.isolates.first.id);
        scripts = await setup.service.getScripts(isolate.id);

        await setup.service.streamListen('Debug');
        stream = setup.service.onEvent('Debug');

        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      tearDown(() async {
        await setup.service.resume(isolate.id);
      });

      test('cannot evaluate expression', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          expect(
              () => setup.service
                  .evaluateInFrame(isolate.id, event.topFrame.index, 'local'),
              throwsRPCError);
        });
      });
    });
  });
}
