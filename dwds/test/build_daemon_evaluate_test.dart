// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
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

  static final contextSound = TestContext(
      directory: p.join('..', 'fixtures', '_testPackageSound'),
      entry: p.join('..', 'fixtures', '_testPackageSound', 'web', 'main.dart'),
      path: 'index.html',
      pathToServe: 'web');

  TestContext context;

  TestSetup.sound() : context = contextSound;

  TestSetup.unsound() : context = contextUnsound;

  ChromeProxyService get service =>
      fetchChromeProxyService(context.debugConnection);
  WipConnection get tabConnection => context.tabConnection;

  /// Redirect the logs for the current zone to emit on failure.
  ///
  /// All messages are stored and reported on test failure.
  /// Needs to be called in both setUpAll() and setUp() to store
  /// the logs in the current zone.
  ///
  /// Note: change 'printOnFailure' to 'print' for debug printing.
  static void setCurrentLogWriter() {
    configureLogWriter(
        customLogWriter: (level, message,
                {loggerName, error, stackTrace, verbose}) =>
            printOnFailure('[$level] $loggerName: $message'));
  }
}

void main() async {
  for (var soundNullSafety in [false, true]) {
    var setup = soundNullSafety ? TestSetup.sound() : TestSetup.unsound();
    var context = setup.context;
    group('${soundNullSafety ? "" : "no "}sound null safety', () {
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
          TestSetup.setCurrentLogWriter();
          await context.setUp(enableExpressionEvaluation: true, verbose: false);
        });

        tearDownAll(() async {
          await context.tearDown();
        });

        setUp(() async {
          TestSetup.setCurrentLogWriter();
        });

        group('evaluateInFrame', () {
          VM vm;
          Isolate isolate;
          ScriptList scripts;
          ScriptRef mainScript;
          ScriptRef libraryScript;
          ScriptRef testLibraryScript;
          ScriptRef testLibraryPartScript;
          Stream<Event> stream;

          setUp(() async {
            vm = await setup.service.getVM();
            isolate = await setup.service.getIsolate(vm.isolates.first.id);
            scripts = await setup.service.getScripts(isolate.id);

            await setup.service.streamListen('Debug');
            stream = setup.service.onEvent('Debug');

            mainScript = scripts.scripts
                .firstWhere((each) => each.uri.contains('main.dart'));
            testLibraryScript = scripts.scripts.firstWhere((each) =>
                each.uri.contains('package:_test_package/test_library.dart'));
            testLibraryPartScript = scripts.scripts.firstWhere((each) =>
                each.uri.contains('package:_test_package/src/test_part.dart'));
            libraryScript = scripts.scripts.firstWhere(
                (each) => each.uri.contains('package:_test/library.dart'));
          });

          tearDown(() async {
            await setup.service.resume(isolate.id);
          });

          test('local', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service
                  .evaluateInFrame(isolate.id, event.topFrame.index, 'local');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '42'));
            });
          });

          test('field', () async {
            await onBreakPoint(
                isolate.id, mainScript, 'printFieldFromLibraryClass', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'instance.field');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '1'));
            });
          });

          test('private field from another library', () async {
            await onBreakPoint(
                isolate.id, mainScript, 'printFieldFromLibraryClass', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'instance._field');

              expect(
                  result,
                  isA<ErrorRef>().having(
                      (instance) => instance.message,
                      'message',
                      contains("The getter '_field' isn't defined")));
            });
          });

          test('private field from current library', () async {
            await onBreakPoint(isolate.id, mainScript, 'printFieldMain',
                () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'instance._field');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '1'));
            });
          });

          test('access instance fields after evaluation', () async {
            await onBreakPoint(
                isolate.id, mainScript, 'printFieldFromLibraryClass', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var instanceRef = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'instance') as InstanceRef;

              var instance = await setup.service
                  .getObject(isolate.id, instanceRef.id) as Instance;

              var field = instance.fields.firstWhere(
                  (BoundField element) => element.decl.name == 'field');

              expect(
                  field.value,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '1'));
            });
          });

          test('global', () async {
            await onBreakPoint(isolate.id, mainScript, 'printGlobal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'testLibraryValue');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '3'));
            });
          });

          test('call core function', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'print(local)');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      'null'));
            });
          });

          test('call library function with const param', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'testLibraryFunction(42)');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '42'));
            });
          });

          test('call library function with local param', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(isolate.id,
                  event.topFrame.index, 'testLibraryFunction(local)');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '42'));
            });
          });

          test('call library part function with const param', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(isolate.id,
                  event.topFrame.index, 'testLibraryPartFunction(42)');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '42'));
            });
          });

          test('call library part function with local param', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(isolate.id,
                  event.topFrame.index, 'testLibraryPartFunction(local)');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '42'));
            });
          });

          test('loop variable', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLoopVariable',
                () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service
                  .evaluateInFrame(isolate.id, event.topFrame.index, 'item');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '1'));
            });
          });

          test('evaluate expression in _test_package/test_library', () async {
            await onBreakPoint(
                isolate.id, testLibraryScript, 'testLibraryFunction', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service
                  .evaluateInFrame(isolate.id, event.topFrame.index, 'formal');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '23'));
            });
          });

          test('evaluate expression in a class constructor in a library',
              () async {
            await onBreakPoint(
                isolate.id, testLibraryScript, 'testLibraryClassConstructor',
                () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'this.field');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '1'));
            });
          });

          test('evaluate expression in a class constructor in a library part',
              () async {
            await onBreakPoint(isolate.id, testLibraryPartScript,
                'testLibraryPartClassConstructor', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index, 'this.field');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '1'));
            });
          });

          test('evaluate expression in caller frame', () async {
            await onBreakPoint(
                isolate.id, testLibraryScript, 'testLibraryFunction', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service.evaluateInFrame(
                  isolate.id, event.topFrame.index + 1, 'local');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      '23'));
            });
          });

          test('evaluate expression in a library', () async {
            await onBreakPoint(isolate.id, libraryScript, 'Concatenate',
                () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var result = await setup.service
                  .evaluateInFrame(isolate.id, event.topFrame.index, 'a');

              expect(
                  result,
                  isA<InstanceRef>().having(
                      (instance) => instance.valueAsString,
                      'valueAsString',
                      'Hello'));
            });
          });

          test('error', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              var error = await setup.service
                  .evaluateInFrame(isolate.id, event.topFrame.index, 'typo');

              expect(
                  error,
                  isA<ErrorRef>().having(
                      (instance) => instance.message,
                      'message',
                      matches('CompilationError: Getter not found:.*typo')));
            });
          });

          test('cannot evaluate in unsupported isolate', () async {
            await onBreakPoint(isolate.id, mainScript, 'printLocal', () async {
              var event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              expect(
                  () => setup.service
                      .evaluateInFrame('bad', event.topFrame.index, 'local'),
                  throwsRPCError);
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
            var library = isolate.rootLib;
            var result = await setup.service
                .evaluate(isolate.id, library.id, 'MainClass(0).toString()');

            expect(
                result,
                const TypeMatcher<InstanceRef>().having(
                    (instance) => instance.valueAsString,
                    'valueAsString',
                    '0'));
          });

          test('uses symbol from another library', () async {
            var library = isolate.rootLib;
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
            var library = isolate.rootLib;
            var result = await setup.service
                .evaluate(isolate.id, library.id, '(() => 42)()');

            expect(
                result,
                const TypeMatcher<InstanceRef>().having(
                    (instance) => instance.valueAsString,
                    'valueAsString',
                    '42'));
          });
        });
      }, timeout: const Timeout.factor(2));

      group('shared context with no evaluation', () {
        setUpAll(() async {
          TestSetup.setCurrentLogWriter();
          await context.setUp(
              enableExpressionEvaluation: false, verbose: false);
        });

        tearDownAll(() async {
          await context.tearDown();
        });

        setUp(() async {
          TestSetup.setCurrentLogWriter();
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
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              expect(
                  () => setup.service.evaluateInFrame(
                      isolate.id, event.topFrame.index, 'local'),
                  throwsRPCError);
            });
          });
        });
      });
    });
  }
}
