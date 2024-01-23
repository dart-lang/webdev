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
  final context =
      TestContext(TestProject.testExperimentWithSoundNullSafety, provider);
  final testInspector = TestInspector(context);

  late VmService service;
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

  getObject(instanceId) => service.getObject(isolateId, instanceId);

  getInstanceRef(frame, expression) =>
      testInspector.getInstanceRef(isolateId, frame, expression);

  getDisplayedFields(InstanceRef ref) =>
      testInspector.getDisplayedFields(isolateId, ref);

  getDisplayedGetters(InstanceRef ref) =>
      testInspector.getDisplayedGetters(isolateId, ref);

  getElements(String instanceId) =>
      testInspector.getElements(isolateId, instanceId);

  final matchDisplayedTypeObjectGetters = {
    'hashCode': matches('[0-9]*'),
    'runtimeType': matchTypeClassName,
  };

  group('$compilationMode |', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          enableExpressionEvaluation: true,
          verboseCompiler: debug,
          experiments: ['records', 'patterns'],
          canaryFeatures: canaryFeatures,
        ),
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

    test('simple record type', () async {
      await onBreakPoint(
        'printSimpleLocalRecord',
        (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
          final instanceId = instanceRef.id!;

          expect(instanceRef, matchRecordTypeInstanceRef(length: 2));
          expect(
            await getObject(instanceId),
            matchRecordTypeInstance(length: 2),
          );

          final classId = instanceRef.classRef!.id;
          expect(await getObject(classId), matchRecordTypeClass);
        },
      );
    });

    test('simple record type elements', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
        final instanceId = instanceRef.id!;

        expect(
          await getElements(instanceId),
          [matchTypeInstance('bool'), matchTypeInstance('int')],
        );
        expect(
          await getDisplayedFields(instanceRef),
          {1: 'bool', 2: 'int'},
        );
      });
    });

    test(
      'simple record type getters',
      () async {
        await onBreakPoint('printSimpleLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');

          expect(
            await getDisplayedGetters(instanceRef),
            matchDisplayedTypeObjectGetters,
          );
        });
      },
      skip: !dartSdkIsAtLeast('3.4.0-56.0.dev'),
    );

    test('simple record type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeStringRef =
            await getInstanceRef(frame, 'record.runtimeType.toString()');
        final typeStringId = typeStringRef.id!;

        expect(
          await getObject(typeStringId),
          matchPrimitiveInstance(
            kind: InstanceKind.kString,
            value: '(bool, int)',
          ),
        );
      });
    });

    test(
      'complex record type',
      () async {
        await onBreakPoint('printComplexLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
          final instanceId = instanceRef.id!;

          expect(instanceRef, matchRecordTypeInstanceRef(length: 3));
          expect(
            await getObject(instanceId),
            matchRecordTypeInstance(length: 3),
          );

          final classId = instanceRef.classRef!.id;
          expect(await getObject(classId), matchRecordTypeClass);
        });
      },
    );

    test('complex record type elements', () async {
      await onBreakPoint('printComplexLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
        final instanceId = instanceRef.id!;

        expect(
          await getElements(instanceId),
          [
            matchTypeInstance('bool'),
            matchTypeInstance('int'),
            matchTypeInstance('IdentityMap<String, int>'),
          ],
        );
        expect(
          await getDisplayedFields(instanceRef),
          {1: 'bool', 2: 'int', 3: 'IdentityMap<String, int>'},
        );
      });
    });

    test(
      'complex record type getters',
      () async {
        await onBreakPoint('printComplexLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');

          expect(
            await getDisplayedGetters(instanceRef),
            matchDisplayedTypeObjectGetters,
          );
        });
      },
      skip: !dartSdkIsAtLeast('3.4.0-56.0.dev'),
    );

    test('complex record type display', () async {
      await onBreakPoint('printComplexLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeStringRef =
            await getInstanceRef(frame, 'record.runtimeType.toString()');
        final typeStringId = typeStringRef.id!;

        expect(
          await getObject(typeStringId),
          matchPrimitiveInstance(
            kind: InstanceKind.kString,
            value: '(bool, int, IdentityMap<String, int>)',
          ),
        );
      });
    });

    test('complex record type with named fields ', () async {
      await onBreakPoint('printComplexNamedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
        final instanceId = instanceRef.id!;

        expect(instanceRef, matchRecordTypeInstanceRef(length: 3));
        expect(
          await getObject(instanceId),
          matchRecordTypeInstance(length: 3),
        );

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchRecordTypeClass);
      });
    });

    test('complex record type with named fields elements', () async {
      await onBreakPoint('printComplexNamedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
        final instanceId = instanceRef.id!;

        expect(
          await getElements(instanceId),
          [
            matchTypeInstance('bool'),
            matchTypeInstance('int'),
            matchTypeInstance('IdentityMap<String, int>'),
          ],
        );

        expect(
          await getDisplayedFields(instanceRef),
          {1: 'bool', 2: 'int', 'array': 'IdentityMap<String, int>'},
        );
      });
    });

    test(
      'complex record type with named fields getters',
      () async {
        await onBreakPoint('printComplexNamedLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');

          expect(
            await getDisplayedGetters(instanceRef),
            matchDisplayedTypeObjectGetters,
          );
        });
      },
      skip: !dartSdkIsAtLeast('3.4.0-56.0.dev'),
    );

    test('complex record type with named fields display', () async {
      await onBreakPoint('printComplexNamedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeStringRef =
            await getInstanceRef(frame, 'record.runtimeType.toString()');
        final typeStringId = typeStringRef.id!;

        expect(
          await getObject(typeStringId),
          matchPrimitiveInstance(
            kind: InstanceKind.kString,
            value: '(bool, int, {IdentityMap<String, int> array})',
          ),
        );
      });
    });

    test(
      'nested record type',
      () async {
        await onBreakPoint('printNestedLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
          final instanceId = instanceRef.id!;

          expect(instanceRef, matchRecordTypeInstanceRef(length: 2));
          expect(
            await getObject(instanceId),
            matchRecordTypeInstance(length: 2),
          );

          final classId = instanceRef.classRef!.id;
          expect(await getObject(classId), matchRecordTypeClass);
        });
      },
    );

    test('nested record type elements', () async {
      await onBreakPoint('printNestedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
        final instanceId = instanceRef.id!;

        final elements = await getElements(instanceId);
        expect(
          elements,
          [matchTypeInstance('bool'), matchRecordTypeInstance(length: 2)],
        );
        expect(
          await getElements(elements[1].id!),
          [matchTypeInstance('bool'), matchTypeInstance('int')],
        );
        expect(
          await getDisplayedFields(instanceRef),
          {1: 'bool', 2: '(bool, int)'},
        );
        expect(
          await getDisplayedFields(elements[1]),
          {1: 'bool', 2: 'int'},
        );
      });
    });

    test(
      'nested record type getters',
      () async {
        await onBreakPoint('printNestedLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
          final elements = await getElements(instanceRef.id!);

          expect(
            await getDisplayedGetters(instanceRef),
            matchDisplayedTypeObjectGetters,
          );
          expect(
            await getDisplayedGetters(elements[1]),
            matchDisplayedTypeObjectGetters,
          );
        });
      },
      skip: !dartSdkIsAtLeast('3.4.0-56.0.dev'),
    );

    test('nested record type display', () async {
      await onBreakPoint('printNestedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeStringRef =
            await getInstanceRef(frame, 'record.runtimeType.toString()');
        final typeStringId = typeStringRef.id!;

        expect(
          await getObject(typeStringId),
          matchPrimitiveInstance(
            kind: InstanceKind.kString,
            value: '(bool, (bool, int))',
          ),
        );
      });
    });

    test('nested record type with named fields', () async {
      await onBreakPoint('printNestedNamedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
        final instanceId = instanceRef.id!;
        final instance = await getObject(instanceId);

        expect(instanceRef, matchRecordTypeInstanceRef(length: 2));
        expect(instance, matchRecordTypeInstance(length: 2));

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchRecordTypeClass);
      });
    });

    test('nested record type with named fields elements', () async {
      await onBreakPoint('printNestedNamedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
        final instanceId = instanceRef.id!;

        final elements = await getElements(instanceId);
        expect(
          elements,
          [matchTypeInstance('bool'), matchRecordTypeInstance(length: 2)],
        );
        expect(
          await getElements(elements[1].id!),
          [matchTypeInstance('bool'), matchTypeInstance('int')],
        );
        expect(
          await getDisplayedFields(instanceRef),
          {1: 'bool', 'inner': '(bool, int)'},
        );

        expect(
          await getDisplayedFields(elements[1]),
          {1: 'bool', 2: 'int'},
        );
      });
    });

    test(
      'nested record type with named fields getters',
      () async {
        await onBreakPoint('printNestedNamedLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
          final elements = await getElements(instanceRef.id!);

          expect(
            await getDisplayedGetters(instanceRef),
            matchDisplayedTypeObjectGetters,
          );
          expect(
            await getDisplayedGetters(elements[1]),
            matchDisplayedTypeObjectGetters,
          );
        });
      },
      skip: !dartSdkIsAtLeast('3.4.0-56.0.dev'),
    );

    test(
      'nested record type with named fields display',
      () async {
        await onBreakPoint('printNestedNamedLocalRecord', (event) async {
          final frame = event.topFrame!.index!;
          final instanceRef = await getInstanceRef(frame, 'record.runtimeType');
          final instance = await getObject(instanceRef.id!);
          final typeClassId = instance.classRef!.id;

          expect(await getObject(typeClassId), matchRecordTypeClass);

          final typeStringRef =
              await getInstanceRef(frame, 'record.runtimeType.toString()');
          final typeStringId = typeStringRef.id!;

          expect(
            await getObject(typeStringId),
            matchPrimitiveInstance(
              kind: InstanceKind.kString,
              value: '(bool, {(bool, int) inner})',
            ),
          );
        });
      },
    );
  });
}
