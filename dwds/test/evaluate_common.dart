// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
import 'dart:async';

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'fixtures/context.dart';

class TestSetup {
  static TestContext contextUnsound(String index) =>
      TestContext.withWeakNullSafety(
        packageName: '_testPackage',
        webAssetsPath: 'web',
        dartEntryFileName: 'main.dart',
        htmlEntryFileName: index,
      );

  static TestContext contextSound(String index) =>
      TestContext.withSoundNullSafety(
        packageName: '_testPackageSound',
        webAssetsPath: 'web',
        dartEntryFileName: 'main.dart',
        htmlEntryFileName: index,
      );

  TestContext context;

  TestSetup.sound(IndexBaseMode baseMode)
      : context = contextSound(_index(baseMode));

  TestSetup.unsound(IndexBaseMode baseMode)
      : context = contextUnsound(_index(baseMode));

  factory TestSetup.create(NullSafety? nullSafety, IndexBaseMode baseMode) =>
      nullSafety == NullSafety.sound
          ? TestSetup.sound(baseMode)
          : TestSetup.unsound(baseMode);

  ChromeProxyService get service =>
      fetchChromeProxyService(context.debugConnection);
  WipConnection get tabConnection => context.tabConnection;

  static String _index(IndexBaseMode baseMode) =>
      baseMode == IndexBaseMode.base ? 'base_index.html' : 'index.html';
}

void testAll({
  CompilationMode compilationMode = CompilationMode.buildDaemon,
  IndexBaseMode indexBaseMode = IndexBaseMode.noBase,
  NullSafety nullSafety = NullSafety.sound,
  bool useDebuggerModuleNames = false,
  bool debug = false,
}) {
  if (compilationMode == CompilationMode.buildDaemon &&
      indexBaseMode == IndexBaseMode.base) {
    throw StateError(
        'build daemon scenario does not support non-empty base in index file');
  }
  final setup = TestSetup.create(nullSafety, indexBaseMode);
  final context = setup.context;

  Future<void> onBreakPoint(String isolate, ScriptRef script,
      String breakPointId, Future<void> Function() body) async {
    Breakpoint? bp;
    try {
      final line =
          await context.findBreakpointLine(breakPointId, isolate, script);
      bp = await setup.service
          .addBreakpointWithScriptUri(isolate, script.uri!, line);
      await body();
    } finally {
      // Remove breakpoint so it doesn't impact other tests or retries.
      if (bp != null) {
        await setup.service.removeBreakpoint(isolate, bp.id!);
      }
    }
  }

  group('shared context with evaluation |', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        compilationMode: compilationMode,
        enableExpressionEvaluation: true,
        useDebuggerModuleNames: useDebuggerModuleNames,
        verboseCompiler: debug,
      );
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    setUp(() => setCurrentLogWriter(debug: debug));

    group('evaluateInFrame |', () {
      VM vm;
      late Isolate isolate;
      late String isolateId;
      ScriptList scripts;
      late ScriptRef mainScript;
      late ScriptRef libraryScript;
      late ScriptRef testLibraryScript;
      late ScriptRef testLibraryPartScript;
      late Stream<Event> stream;

      setUp(() async {
        setCurrentLogWriter(debug: debug);
        vm = await setup.service.getVM();
        isolate = await setup.service.getIsolate(vm.isolates!.first.id!);
        isolateId = isolate.id!;
        scripts = await setup.service.getScripts(isolateId);

        await setup.service.streamListen('Debug');
        stream = setup.service.onEvent('Debug');

        final soundNullSafety = nullSafety == NullSafety.sound;
        final testPackage =
            soundNullSafety ? '_test_package_sound' : '_test_package';
        final test = soundNullSafety ? '_test_sound' : '_test';
        mainScript = scripts.scripts!
            .firstWhere((each) => each.uri!.contains('main.dart'));
        testLibraryScript = scripts.scripts!.firstWhere((each) =>
            each.uri!.contains('package:$testPackage/test_library.dart'));
        testLibraryPartScript = scripts.scripts!.firstWhere((each) =>
            each.uri!.contains('package:$testPackage/src/test_part.dart'));
        libraryScript = scripts.scripts!.firstWhere(
            (each) => each.uri!.contains('package:$test/library.dart'));
      });

      tearDown(() async {
        await setup.service.resume(isolateId);
      });

      test('uses correct null safety mode', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final isNullSafetyEnabled =
              '() { const sound = !(<Null>[] is List<int>); return sound; } ()';
          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, isNullSafetyEnabled);

          expect(
              result,
              isA<InstanceRef>().having((instance) => instance.valueAsString,
                  'valueAsString', '${nullSafety == NullSafety.sound}'));
        });
      });

      test('does not crash if class metadata cannot be found', () async {
        await onBreakPoint(isolateId, mainScript, 'printStream', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'stream');
          final instanceId = (result as InstanceRef).id!;
          final instance = await setup.service.getObject(isolateId, instanceId);

          expect(
              instance,
              isA<Instance>().having((instance) => instance.classRef!.name,
                  'class name', '_AsBroadcastStream<int>'));
        });
      });

      test('with scope override is not supported yet', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final object = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'MainClass(1,0)');

          final param = object as InstanceRef;
          final result = await setup.service.evaluateInFrame(
            isolateId,
            event.topFrame!.index!,
            't.toString()',
            scope: {'t': param.id!},
          );

          expect(
              result,
              isA<ErrorRef>().having(
                  (instance) => instance.message,
                  'message',
                  contains('Using scope for expression evaluation '
                      'in frame is not supported')));
        });
      });

      test('local', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'local');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('Type does not show native JavaScript object fields', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          Future<Instance> getInstance(InstanceRef ref) async {
            final result = await setup.service.getObject(isolateId, ref.id!);
            expect(result, isA<Instance>());
            return result as Instance;
          }

          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'Type');
          expect(result, isA<InstanceRef>());
          final instanceRef = result as InstanceRef;

          // Type
          var instance = await getInstance(instanceRef);
          for (var field in instance.fields!) {
            final name = field.decl!.name;

            // Type.<name> (i.e. Type._type)
            instance = await getInstance(field.value as InstanceRef);
            for (var field in instance.fields!) {
              final nestedName = field.decl!.name;

              // Type.<name>.<nestedName> (i.e Type._type._subtypeCache)
              instance = await getInstance(field.value as InstanceRef);

              expect(
                  instance,
                  isA<Instance>().having(
                      (instance) => instance.classRef!.name,
                      'Type.$name.$nestedName: classRef.name',
                      isNot(isIn([
                        'NativeJavaScriptObject',
                        'JavaScriptObject',
                      ]))));
            }
          }
        });
      });

      test('field', () async {
        await onBreakPoint(isolateId, mainScript, 'printFieldFromLibraryClass',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'instance.field');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('private field from another library', () async {
        await onBreakPoint(isolateId, mainScript, 'printFieldFromLibraryClass',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'instance._field');

          expect(
              result,
              isA<ErrorRef>().having((instance) => instance.message, 'message',
                  contains("The getter '_field' isn't defined")));
        });
      });

      test('private field from current library', () async {
        await onBreakPoint(isolateId, mainScript, 'printFieldMain', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'instance._field');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('access instance fields after evaluation', () async {
        await onBreakPoint(isolateId, mainScript, 'printFieldFromLibraryClass',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final instanceRef = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'instance') as InstanceRef;

          final instance = await setup.service
              .getObject(isolateId, instanceRef.id!) as Instance;

          final field = instance.fields!.firstWhere(
              (BoundField element) => element.decl!.name == 'field');

          expect(
              field.value,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('global', () async {
        await onBreakPoint(isolateId, mainScript, 'printGlobal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'testLibraryValue');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '3'));
        });
      });

      test('call core function', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'print(local)');

          expect(
              result,
              isA<InstanceRef>().having((instance) => instance.valueAsString,
                  'valueAsString', 'null'));
        });
      });

      test('call library function with const param', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'testLibraryFunction(42)');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('call library function with local param', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'testLibraryFunction(local)');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('call library part function with const param', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'testLibraryPartFunction(42)');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('call library part function with local param', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service.evaluateInFrame(isolateId,
              event.topFrame!.index!, 'testLibraryPartFunction(local)');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '42'));
        });
      });

      test('loop variable', () async {
        await onBreakPoint(isolateId, mainScript, 'printLoopVariable',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'item');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('evaluate expression in _test_package/test_library', () async {
        await onBreakPoint(isolateId, testLibraryScript, 'testLibraryFunction',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'formal');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '23'));
        });
      });

      test('evaluate expression in a class constructor in a library', () async {
        await onBreakPoint(
            isolateId, testLibraryScript, 'testLibraryClassConstructor',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'this.field');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('evaluate expression in a class constructor in a library part',
          () async {
        await onBreakPoint(
            isolateId, testLibraryPartScript, 'testLibraryPartClassConstructor',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'this.field');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '1'));
        });
      });

      test('evaluate expression in caller frame', () async {
        await onBreakPoint(isolateId, testLibraryScript, 'testLibraryFunction',
            () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index! + 1, 'local');

          expect(
              result,
              isA<InstanceRef>().having(
                  (instance) => instance.valueAsString, 'valueAsString', '23'));
        });
      });

      test('evaluate expression in a library', () async {
        await onBreakPoint(isolateId, libraryScript, 'Concatenate', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final result = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'a');

          expect(
              result,
              isA<InstanceRef>().having((instance) => instance.valueAsString,
                  'valueAsString', 'Hello'));
        });
      });

      test('compilation error', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final error = await setup.service
              .evaluateInFrame(isolateId, event.topFrame!.index!, 'typo');

          expect(
              error,
              isA<ErrorRef>().having((instance) => instance.message, 'message',
                  contains('CompilationError:')));
        });
      });

      test('module load error', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          final error = await setup.service.evaluateInFrame(
              isolateId, event.topFrame!.index!, 'd.deferredPrintLocal()');

          expect(
              error,
              isA<ErrorRef>().having((instance) => instance.message, 'message',
                  contains('LoadModuleError:')));
        });
      }, skip: 'https://github.com/dart-lang/sdk/issues/48587');

      test('cannot evaluate in unsupported isolate', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          await expectLater(
              setup.service
                  .evaluateInFrame('bad', event.topFrame!.index!, 'local'),
              throwsSentinelException);
        });
      });
    });

    group('evaluate |', () {
      VM vm;
      late Isolate isolate;
      late String isolateId;

      setUp(() async {
        setCurrentLogWriter(debug: debug);
        vm = await setup.service.getVM();
        isolate = await setup.service.getIsolate(vm.isolates!.first.id!);
        isolateId = isolate.id!;

        await setup.service.streamListen('Debug');
      });

      tearDown(() async {});

      test('in parallel (in a batch)', () async {
        final library = isolate.rootLib!;
        final evaluation1 = setup.service
            .evaluate(isolateId, library.id!, 'MainClass(1,0).toString()');
        final evaluation2 = setup.service
            .evaluate(isolateId, library.id!, 'MainClass(1,1).toString()');

        final results = await Future.wait([evaluation1, evaluation2]);
        expect(
            results[0],
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '1, 0'));

        expect(
            results[1],
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '1, 1'));
      });

      test('in parallel (in a batch) handles errors', () async {
        final library = isolate.rootLib!;
        final missingLibId = '';
        final evaluation1 = setup.service
            .evaluate(isolateId, missingLibId, 'MainClass(1,0).toString()');
        final evaluation2 = setup.service
            .evaluate(isolateId, library.id!, 'MainClass(1,1).toString()');

        final results = await Future.wait([evaluation1, evaluation2]);

        expect(
            results[0],
            isA<ErrorRef>().having(
              (instance) => instance.message,
              'message',
              contains('No batch result object ID'),
            ));
        expect(
            results[1],
            isA<ErrorRef>().having(
              (instance) => instance.message,
              'message',
              contains('No batch result object ID'),
            ));
      });

      test('with scope override', () async {
        final library = isolate.rootLib!;
        final object = await setup.service
            .evaluate(isolateId, library.id!, 'MainClass(1,0)');

        final param = object as InstanceRef;
        final result = await setup.service.evaluate(
            isolateId, library.id!, 't.toString()',
            scope: {'t': param.id!});

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '1, 0'));
      });

      test('uses symbol from the same library', () async {
        final library = isolate.rootLib!;
        final result = await setup.service
            .evaluate(isolateId, library.id!, 'MainClass(1,0).toString()');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '1, 0'));
      });

      test('uses symbol from another library', () async {
        final library = isolate.rootLib!;
        final result = await setup.service.evaluate(
            isolateId, library.id!, 'TestLibraryClass(0,1).toString()');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString,
                'valueAsString',
                'field: 0, _field: 1'));
      });

      test('closure call', () async {
        final library = isolate.rootLib!;
        final result = await setup.service
            .evaluate(isolateId, library.id!, '(() => 42)()');

        expect(
            result,
            const TypeMatcher<InstanceRef>().having(
                (instance) => instance.valueAsString, 'valueAsString', '42'));
      });
    });
  }, timeout: const Timeout.factor(2));

  group('shared context with no evaluation |', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        compilationMode: compilationMode,
        enableExpressionEvaluation: false,
        verboseCompiler: debug,
      );
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    setUp(() => setCurrentLogWriter(debug: debug));

    group('evaluateInFrame |', () {
      VM vm;
      late Isolate isolate;
      late String isolateId;
      ScriptList scripts;
      late ScriptRef mainScript;
      late Stream<Event> stream;

      setUp(() async {
        vm = await setup.service.getVM();
        isolate = await setup.service.getIsolate(vm.isolates!.first.id!);
        isolateId = isolate.id!;
        scripts = await setup.service.getScripts(isolateId);

        await setup.service.streamListen('Debug');
        stream = setup.service.onEvent('Debug');

        mainScript = scripts.scripts!
            .firstWhere((each) => each.uri!.contains('main.dart'));
      });

      tearDown(() async {
        await setup.service.resume(isolateId);
      });

      test('cannot evaluate expression', () async {
        await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
          final event = await stream
              .firstWhere((event) => event.kind == EventKind.kPauseBreakpoint);

          await expectLater(
              setup.service
                  .evaluateInFrame(isolateId, event.topFrame!.index!, 'local'),
              throwsRPCError);
        });
      });
    });
  });
}
