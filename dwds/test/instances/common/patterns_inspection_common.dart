// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:test_common/utilities.dart';
import 'package:vm_service/vm_service.dart';

import '../../fixtures/context.dart';
import '../../fixtures/project.dart';
import '../../fixtures/utilities.dart';
import 'test_inspector.dart';

void runTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
  required bool canaryFeatures,
  required bool debug,
}) {
  final context = TestContext(TestProject.testExperiment, provider);
  final testInspector = TestInspector(context);

  late VmService service;
  late Stream<Event> stream;
  late String isolateId;
  late ScriptRef mainScript;

  Future<void> onBreakPoint(breakPointId, body) => testInspector.onBreakPoint(
    stream,
    isolateId,
    mainScript,
    breakPointId,
    body,
  );

  Future<InstanceRef> getInstanceRef(frame, expression) =>
      testInspector.getInstanceRef(isolateId, frame, expression);

  Future<Map<Object?, Object?>> getFields(instanceRef, {offset, count}) =>
      testInspector.getFields(
        isolateId,
        instanceRef,
        offset: offset,
        count: count,
      );

  Future<Map<String?, Instance?>> getFrameVariables(Frame frame) =>
      testInspector.getFrameVariables(isolateId, frame);

  group('$compilationMode |', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          enableExpressionEvaluation: true,
          verboseCompiler: debug,
          experiments: ['dot-shorthands'],
          canaryFeatures: canaryFeatures,
        ),
      );
      service = context.debugConnection.vmService;

      final vm = await service.getVM();
      isolateId = vm.isolates!.first.id!;
      final scripts = await service.getScripts(isolateId);

      await service.streamListen('Debug');
      stream = service.onEvent('Debug');

      mainScript = scripts.scripts!.firstWhere(
        (each) => each.uri!.contains('main.dart'),
      );
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    setUp(() => setCurrentLogWriter(debug: debug));
    tearDown(() => service.resume(isolateId));

    test('pattern match case 1', () async {
      await onBreakPoint('testPatternCase1', (event) async {
        final frame = event.topFrame!;

        expect(await getFrameVariables(frame), {
          'obj': matchListInstance(type: 'Object'),
          'a': matchPrimitiveInstance(kind: InstanceKind.kString, value: 'a'),
          'n': matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 1),
        });
      });
    });

    test('pattern match case 2', () async {
      await onBreakPoint('testPatternCase2', (event) async {
        final frame = event.topFrame!;

        if (dartSdkIsAtLeast('3.7.0-246.0.dev')) {
          expect(await getFrameVariables(frame), {
            'obj': matchListInstance(type: 'Object'),
            // Renamed to avoid shadowing variables from previous case.
            'a\$': matchPrimitiveInstance(
              kind: InstanceKind.kString,
              value: 'b',
            ),
            'n\$': matchPrimitiveInstance(
              kind: InstanceKind.kDouble,
              value: 3.14,
            ),
          });
        } else {
          expect(await getFrameVariables(frame), {
            'obj': matchListInstance(type: 'Object'),
            // Renamed to avoid shadowing variables from previous case.
            'a': matchPrimitiveInstance(kind: InstanceKind.kString, value: 'b'),
            'n': matchPrimitiveInstance(
              kind: InstanceKind.kDouble,
              value: 3.14,
            ),
          });
        }
      });
    });

    test('pattern match default case', () async {
      await onBreakPoint('testPatternDefault', (event) async {
        final frame = event.topFrame!;
        final frameIndex = frame.index!;
        final instanceRef = await getInstanceRef(frameIndex, 'obj');
        expect(await getFields(instanceRef), {0: 0.0, 1: 1.0});

        expect(await getFrameVariables(frame), {
          'obj': matchListInstance(type: 'int'),
        });
      });
    });

    test('stepping through pattern match', () async {
      await onBreakPoint('callTestPattern1', (Event event) async {
        var previousLocation = event.topFrame!.location;
        for (final step in [
          // Make sure we step into the callee.
          for (var i = 0; i < 4; i++) 'Into',
          // Make a few steps inside the callee.
          for (var i = 0; i < 4; i++) 'Over',
        ]) {
          await service.resume(isolateId, step: step);

          event = await stream.firstWhere(
            (e) => e.kind == EventKind.kPauseInterrupted,
          );

          if (step == 'Over') {
            expect(event.topFrame!.code!.name, 'testPattern');
          }

          final location = event.topFrame!.location;
          expect(location, isNot(equals(previousLocation)));
          previousLocation = location;
        }
      });
    });

    test('before instantiation of pattern-matching variables', () async {
      await onBreakPoint('testPattern2Case1', (event) async {
        final frame = event.topFrame!;

        expect(await getFrameVariables(frame), {
          'dog': matchPrimitiveInstance(kind: 'String', value: 'Prismo'),
        });
      });
    });

    test('after instantiation of pattern-matching variables', () async {
      await onBreakPoint('testPattern2Case2', (event) async {
        final frame = event.topFrame!;

        final vars = await getFrameVariables(frame);
        expect(vars, {
          'dog': matchPrimitiveInstance(kind: 'String', value: 'Prismo'),
          'cats': matchListInstance(type: 'String'),
          'firstCat': matchPrimitiveInstance(kind: 'String', value: 'Garfield'),
          'secondCat': matchPrimitiveInstance(kind: 'String', value: 'Tom'),
        });
      });
    });
  });
}
