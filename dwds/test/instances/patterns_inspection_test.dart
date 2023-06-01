// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';

import '../fixtures/context.dart';
import '../fixtures/project.dart';
import 'instance_inspection_common.dart';

void main() async {
  // Enable verbose logging for debugging.
  final debug = false;

  final provider = TestSdkConfigurationProvider(verbose: debug);
  tearDownAll(provider.dispose);

  for (var compilationMode in CompilationMode.values) {
    await _runTests(
      provider: provider,
      compilationMode: compilationMode,
      debug: debug,
    );
  }
}

Future<void> _runTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
  required bool debug,
}) async {
  final context =
      TestContext(TestProject.testExperimentWithSoundNullSafety, provider);
  final testInspector = TestInspector(context);

  late VmServiceInterface service;
  late Stream<Event> stream;
  late String isolateId;
  late ScriptRef mainScript;

  onBreakPoint(breakPointId, body) => testInspector.onBreakPoint(
        stream,
        isolateId,
        mainScript,
        breakPointId,
        body,
      );

  getInstanceRef(frame, expression) =>
      testInspector.getInstanceRef(isolateId, frame, expression);

  getFields(instanceRef, {offset, count}) => testInspector
      .getFields(isolateId, instanceRef, offset: offset, count: count);

  getFrameVariables(Frame frame) =>
      testInspector.getFrameVariables(isolateId, frame);

  group(
    '$compilationMode |',
    () {
      setUpAll(() async {
        setCurrentLogWriter(debug: debug);
        await context.setUp(
          compilationMode: compilationMode,
          enableExpressionEvaluation: true,
          verboseCompiler: debug,
          experiments: ['records', 'patterns'],
        );
        service = context.debugConnection.vmService;

        final vm = await service.getVM();
        isolateId = vm.isolates!.first.id!;
        final scripts = await service.getScripts(isolateId);

        await service.streamListen('Debug');
        stream = service.onEvent('Debug');

        mainScript = scripts.scripts!
            .firstWhere((each) => each.uri!.contains('main.dart'));
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
            'obj': matchListInstance(type: 'List<Object>'),
            'a': matchPrimitiveInstance(kind: InstanceKind.kString, value: 'a'),
            'n': matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 1),
          });
        });
      });

      test('pattern match case 2', () async {
        await onBreakPoint('testPatternCase2', (event) async {
          final frame = event.topFrame!;

          expect(await getFrameVariables(frame), {
            'obj': matchListInstance(type: 'List<Object>'),
            'a': matchPrimitiveInstance(kind: InstanceKind.kString, value: 'b'),
            'n':
                matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 3.14),
          });
        });
      });

      test('pattern match default case', () async {
        await onBreakPoint('testPatternDefault', (event) async {
          final frame = event.topFrame!;
          final frameIndex = frame.index!;
          final instanceRef = await getInstanceRef(frameIndex, 'obj');
          expect(await getFields(instanceRef), [0, 1]);

          expect(await getFrameVariables(frame), {
            'obj': matchListInstance(type: 'List<int>'),
          });
        });
      });

      test('stepping through pattern match', () async {
        await onBreakPoint('callTestPattern1', (Event event) async {
          var previousLocation = event.topFrame!.location;
          for (var step in [
            // Make sure we step into the callee.
            for (var i = 0; i < 4; i++) 'Into',
            // Make a few steps inside the callee.
            for (var i = 0; i < 4; i++) 'Over',
          ]) {
            await service.resume(isolateId, step: step);

            event = await stream
                .firstWhere((e) => e.kind == EventKind.kPauseInterrupted);

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

          expect(
            await getFrameVariables(frame),
            {'dog': matchPrimitiveInstance(kind: 'String', value: 'Prismo')},
          );
        });
      });

      test('after instantiation of pattern-matching variables', () async {
        await onBreakPoint('testPattern2Case2', (event) async {
          final frame = event.topFrame!;

          expect(await getFrameVariables(frame), {
            'dog': matchPrimitiveInstance(kind: 'String', value: 'Prismo'),
            'cats': matchListInstance(type: 'List<String>'),
            'firstCat':
                matchPrimitiveInstance(kind: 'String', value: 'Garfield'),
            'secondCat': matchPrimitiveInstance(kind: 'String', value: 'Tom'),
          });
        });
      });
    }, // TODO(annagrin): Remove when dart 3.0 is stable.
    skip: semver.Version.parse(Platform.version.split(' ')[0]) <
        semver.Version.parse('3.0.0-351.0.dev'),
  );
}
