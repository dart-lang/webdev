// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['expression-compilation-service'])
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

final context = TestContext(
    directory: p.join('..', 'fixtures', '_testPackage'),
    entry: p.join('..', 'fixtures', '_testPackage', 'web', 'main.dart'),
    path: 'index.html',
    pathToServe: 'web');

ChromeProxyService get service =>
    fetchChromeProxyService(context.debugConnection);
WipConnection get tabConnection => context.tabConnection;

void main() async {
  Future<void> onBreakPoint(String isolate, ScriptRef script,
      String breakPointId, Future<void> Function() body) async {
    Breakpoint bp;
    try {
      var line =
          await context.findBreakpointLine(breakPointId, isolate, script);
      bp = await service.addBreakpointWithScriptUri(isolate, script.uri, line);
      await body();
    } finally {
      // Remove breakpoint so it doesn't impact other tests or retries.
      if (bp != null) {
        await service.removeBreakpoint(isolate, bp.id);
      }
    }
  }

  group('shared context with evaluation', () {
    setUpAll(() async {
      // Note: change printOnFailure to print for debug printing
      configureLogWriter(
          customLogWriter: (level, message,
                  {loggerName, error, stackTrace, verbose}) =>
              printOnFailure(message));

      await context.setUp(enableExpressionEvaluation: true, verbose: true);
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('evaluateInFrame', () {
      VM vm;
      Isolate isolate;
      ScriptList scripts;
      ScriptRef mainScript;
      ScriptRef libraryScript;
      ScriptRef testLibraryScript;
      Stream<Event> stream;

      setUp(() async {
        vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
        scripts = await service.getScripts(isolate.id);

        await service.streamListen('Debug');
        stream = service.onEvent('Debug');

        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
        testLibraryScript = scripts.scripts.firstWhere((each) =>
            each.uri.contains('package:_testPackage/test_library.dart'));
        libraryScript = scripts.scripts.firstWhere(
            (each) => each.uri.contains('package:_test/library.dart'));
      });

      tearDown(() async {
        await service.resume(isolate.id);
      });

      test('local', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'local');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('field', () async {
        await onBreakPoint(isolate.id, mainScript, 'printField', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'instance.field');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('private field', () async {
        await onBreakPoint(isolate.id, mainScript, 'printField', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'instance._field');

          expect(
              result,
              const TypeMatcher<ErrorRef>().having(
                  (instance) => instance.message,
                  'message',
                  contains("The getter '_field' isn't defined")));
        });
      });

      test('access instance fields after evaluation', () async {
        await onBreakPoint(isolate.id, mainScript, 'printField', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var instanceRef = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'instance') as InstanceRef;

          var instance =
              await service.getObject(isolate.id, instanceRef.id) as Instance;

          var field = instance.fields
              .firstWhere((BoundField element) => element.decl.name == 'field');

          expect(
              field.value,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('global', () async {
        await onBreakPoint(isolate.id, mainScript, 'printGlobal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
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

          var result = await service.evaluateInFrame(
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

          var result = await service.evaluateInFrame(
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

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'testLibraryFunction(local)');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('evaluate expression in _testPackage/test_library', () async {
        await onBreakPoint(isolate.id, testLibraryScript, 'testLibraryFunction',
            () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'formal');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '23'));
        });
      });

      test(
          'evaluate expression in a class constructor in _testPackage/test_library',
          () async {
        await onBreakPoint(
            isolate.id, testLibraryScript, 'testLibraryClassConstructor',
            () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'this.field');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      },
          skip: 'Scope is not found for constructors:'
              'https://github.com/dart-lang/sdk/issues/43728');

      test('evaluate expression in caller frame', () async {
        await onBreakPoint(isolate.id, testLibraryScript, 'testLibraryFunction',
            () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index + 1, 'local');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '23'));
        });
      });

      test('evaluate expression in  _test/library', () async {
        await onBreakPoint(isolate.id, libraryScript, 'Concatenate', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var result = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'a');

          expect(
              result,
              const TypeMatcher<InstanceRef>().having(
                  (instance) => instance.valueAsString,
                  'valueAsString',
                  'Hello'));
        });
      });

      test('error', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          var error = await service.evaluateInFrame(
              isolate.id, event.topFrame.index, 'typo');

          expect(
              error,
              const TypeMatcher<ErrorRef>().having(
                  (instance) => instance.message,
                  'message',
                  matches('CompilationError: Getter not found:.*typo')));
        });
      });

      test('cannot evaluate in unsupported isolate', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          expect(
              () =>
                  service.evaluateInFrame('bad', event.topFrame.index, 'local'),
              throwsRPCError);
        });
      });
    });
  }, timeout: const Timeout.factor(2));

  group('shared context with no evaluation', () {
    setUpAll(() async {
      await context.setUp(enableExpressionEvaluation: false, verbose: false);
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
        vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates.first.id);
        scripts = await service.getScripts(isolate.id);

        await service.streamListen('Debug');
        stream = service.onEvent('Debug');

        mainScript = scripts.scripts
            .firstWhere((each) => each.uri.contains('main.dart'));
      });

      tearDown(() async {
        await service.resume(isolate.id);
      });

      test('cannot evaluate expression', () async {
        await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
          var event = await stream.firstWhere(
              (Event event) => event.kind == EventKind.kPauseBreakpoint);

          expect(
              () => service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'local'),
              throwsRPCError);
        });
      });
    });
  });
}
