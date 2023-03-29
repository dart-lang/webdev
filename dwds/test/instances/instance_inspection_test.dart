// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

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
    for (var nullSafetyMode in NullSafety.values) {
      await _runTests(
        provider: provider,
        compilationMode: compilationMode,
        nullSafetyMode: nullSafetyMode,
        debug: debug,
      );
    }
  }
}

Future<void> _runTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
  required NullSafety nullSafetyMode,
  required bool debug,
}) async {
  final testPackage = nullSafetyMode == NullSafety.sound
      ? TestProject.testPackageWithSoundNullSafety()
      : TestProject.testPackageWithWeakNullSafety();
  final context = TestContext(testPackage, provider);
  late VmServiceInterface service;
  late Stream<Event> stream;
  late String isolateId;
  late ScriptRef mainScript;

  final testInspector = TestInspector(context);

  onBreakPoint(breakPointId, body) => testInspector.onBreakPoint(
        stream,
        isolateId,
        mainScript,
        breakPointId,
        body,
      );

  getInstance(frame, expression) =>
      testInspector.getInstance(isolateId, frame, expression);

  getObject(instanceId) => service.getObject(isolateId, instanceId);

  getInstanceRef(frame, expression) =>
      testInspector.getInstanceRef(isolateId, frame, expression);

  getFields(instanceRef, {offset, count}) => testInspector
      .getFields(isolateId, instanceRef, offset: offset, count: count);

  group('$nullSafetyMode |', () {
    group('$compilationMode |', () {
      setUpAll(() async {
        setCurrentLogWriter(debug: debug);
        await context.setUp(
          compilationMode: compilationMode,
          enableExpressionEvaluation: true,
          verboseCompiler: debug,
          experiments: ['records'],
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

      tearDownAll(context.tearDown);

      setUp(() => setCurrentLogWriter(debug: debug));
      tearDown(() => service.resume(isolateId));

      group('Object |', () {
        test('type and fields', () async {
          await onBreakPoint('printFieldMain', (event) async {
            final frame = event.topFrame!.index!;
            final instanceRef = await getInstanceRef(frame, 'instance');

            final instanceId = instanceRef.id!;
            expect(
              await getObject(instanceId),
              matchPlainInstance(type: 'MainClass'),
            );

            expect(await getFields(instanceRef), {'_field': 1, 'field': 2});

            // Offsets and counts are ignored for plain object fields.

            // DevTools calls [VmServiceInterface.getObject] with offset=0
            // and count=0 and expects all fields to be returned.
            expect(
              await getFields(instanceRef, offset: 0, count: 0),
              {'_field': 1, 'field': 2},
            );
            expect(
              await getFields(instanceRef, offset: 0),
              {'_field': 1, 'field': 2},
            );
            expect(
              await getFields(instanceRef, offset: 0, count: 1),
              {'_field': 1, 'field': 2},
            );
            expect(
              await getFields(instanceRef, offset: 1),
              {'_field': 1, 'field': 2},
            );
            expect(
              await getFields(instanceRef, offset: 1, count: 0),
              {'_field': 1, 'field': 2},
            );
            expect(
              await getFields(instanceRef, offset: 1, count: 3),
              {'_field': 1, 'field': 2},
            );
          });
        });

        test('field access', () async {
          await onBreakPoint('printFieldMain', (event) async {
            final frame = event.topFrame!.index!;
            expect(
              await getInstance(frame, r'instance.field'),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 2),
            );

            expect(
              await getInstance(frame, r'instance._field'),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 1),
            );
          });
        });
      });

      group('List |', () {
        test('type and fields', () async {
          await onBreakPoint('printList', (event) async {
            final frame = event.topFrame!.index!;
            final instanceRef = await getInstanceRef(frame, 'list');

            final instanceId = instanceRef.id!;
            expect(
              await getObject(instanceId),
              matchListInstance(type: 'List<int>'),
            );

            expect(await getFields(instanceRef), [0, 1, 2]);
            expect(await getFields(instanceRef, offset: 1, count: 0), []);
            expect(await getFields(instanceRef, offset: 0), [0, 1, 2]);
            expect(await getFields(instanceRef, offset: 0, count: 1), [0]);
            expect(await getFields(instanceRef, offset: 1), [1, 2]);
            expect(await getFields(instanceRef, offset: 1, count: 1), [1]);
            expect(await getFields(instanceRef, offset: 1, count: 3), [1, 2]);
            expect(await getFields(instanceRef, offset: 3, count: 3), []);
          });
        });

        test('Element access', () async {
          await onBreakPoint('printList', (event) async {
            final frame = event.topFrame!.index!;
            expect(
              await getInstance(frame, r'list[0]'),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 0),
            );

            expect(
              await getInstance(frame, r"list[1]"),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 1),
            );

            expect(
              await getInstance(frame, r"list[2]"),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 2),
            );
          });
        });
      });

      group('Map |', () {
        test('type and fields', () async {
          await onBreakPoint('printMap', (event) async {
            final frame = event.topFrame!.index!;
            final instanceRef = await getInstanceRef(frame, 'map');

            final instanceId = instanceRef.id!;
            expect(
              await getObject(instanceId),
              matchMapInstance(type: 'IdentityMap<String, int>'),
            );

            expect(await getFields(instanceRef), {'a': 1, 'b': 2, 'c': 3});

            expect(await getFields(instanceRef, offset: 1, count: 0), {});
            expect(
              await getFields(instanceRef, offset: 0),
              {'a': 1, 'b': 2, 'c': 3},
            );
            expect(await getFields(instanceRef, offset: 0, count: 1), {'a': 1});
            expect(await getFields(instanceRef, offset: 1), {'b': 2, 'c': 3});
            expect(await getFields(instanceRef, offset: 1, count: 1), {'b': 2});
            expect(
              await getFields(instanceRef, offset: 1, count: 3),
              {'b': 2, 'c': 3},
            );
            expect(await getFields(instanceRef, offset: 3, count: 3), {});
          });
        });

        test('Element access', () async {
          await onBreakPoint('printMap', (event) async {
            final frame = event.topFrame!.index!;
            expect(
              await getInstance(frame, r"map['a']"),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 1),
            );

            expect(
              await getInstance(frame, r"map['b']"),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 2),
            );

            expect(
              await getInstance(frame, r"map['c']"),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 3),
            );
          });
        });
      });

      group('Set |', () {
        test('type and fields', () async {
          await onBreakPoint('printSet', (event) async {
            final frame = event.topFrame!.index!;
            final instanceRef = await getInstanceRef(frame, 'mySet');

            final instanceId = instanceRef.id!;
            expect(
              await getObject(instanceId),
              matchSetInstance(type: '_HashSet<int>'),
            );

            expect(await getFields(instanceRef), [1, 4, 5, 7]);
            expect(await getFields(instanceRef, offset: 0), [1, 4, 5, 7]);
            expect(await getFields(instanceRef, offset: 1, count: 2), [4, 5]);
            expect(await getFields(instanceRef, offset: 2), [5, 7]);
            expect(await getFields(instanceRef, offset: 2, count: 10), [5, 7]);
            expect(await getFields(instanceRef, offset: 1, count: 0), []);
            expect(await getFields(instanceRef, offset: 10, count: 2), []);
          });
        });

        test('Element access', () async {
          await onBreakPoint('printSet', (event) async {
            final frame = event.topFrame!.index!;
            expect(
              await getInstance(frame, r"mySet.first"),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 1),
            );
            expect(
              await getInstance(frame, r"mySet.last"),
              matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 7),
            );
          });
        });
      });
    });
  });
}
