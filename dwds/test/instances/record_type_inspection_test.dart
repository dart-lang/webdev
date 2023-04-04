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

  getObject(instanceId) => service.getObject(isolateId, instanceId);

  getInstanceRef(frame, expression) =>
      testInspector.getInstanceRef(isolateId, frame, expression);

  getFields(instanceRef, {offset, count, depth = -1}) =>
      testInspector.getFields(
        isolateId,
        instanceRef,
        offset: offset,
        count: count,
        depth: depth,
      );

  getUnwrappedTypeInstanceRef(ref) =>
      testInspector.getUnwrappedTypeInstanceRef(isolateId, ref);

  getUnwrappedTypeInstance(ref) =>
      testInspector.getUnwrappedTypeInstance(isolateId, ref);

  group('$compilationMode |', () {
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

    Future<List<String?>> getRecordFieldTypes(InstanceRef ref) async {
      final typeInstanceRef = await getUnwrappedTypeInstanceRef(ref);
      final classId = typeInstanceRef.classRef!.id;

      expect(await getObject(classId), matchRecordTypeClass);

      final fieldTypeInstanceRefs = await getFields(typeInstanceRef, depth: 1)
          as Map<dynamic, InstanceRef>;

      final fieldTypes = await Future.wait(
        fieldTypeInstanceRefs.values.map(
          (ref) async =>
              await service.invoke(isolateId, ref.id!, 'toString', []),
        ),
      );

      return fieldTypes
          .map((ref) => (ref as InstanceRef).valueAsString)
          .toList();
    }

    test('simple record type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeInstanceRef =
            await getInstanceRef(frame, 'record.runtimeType');

        expect(
          await getUnwrappedTypeInstance(typeInstanceRef),
          matchRecordTypeInstance(length: 2),
        );

        expect(
          await getRecordFieldTypes(typeInstanceRef),
          ['bool', 'int'],
        );
      });
    });

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

    test('complex record type', () async {
      await onBreakPoint('printComplexLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeInstanceRef =
            await getInstanceRef(frame, 'record.runtimeType');

        expect(
          await getUnwrappedTypeInstance(typeInstanceRef),
          matchRecordTypeInstance(length: 3),
        );

        expect(
          await getRecordFieldTypes(typeInstanceRef),
          ['bool', 'int', 'IdentityMap<String, int>'],
        );
      });
    });

    test('complex records display', () async {
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
        final typeInstanceRef =
            await getInstanceRef(frame, 'record.runtimeType');

        expect(
          await getUnwrappedTypeInstance(typeInstanceRef),
          matchRecordTypeInstance(length: 3),
        );

        expect(
          await getRecordFieldTypes(typeInstanceRef),
          ['bool', 'int', 'IdentityMap<String, int>'],
        );
      });
    });

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

    test('nested record type display', () async {
      await onBreakPoint('printNestedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeInstanceRef =
            await getInstanceRef(frame, 'record.runtimeType');

        expect(
          await getUnwrappedTypeInstance(typeInstanceRef),
          matchRecordTypeInstance(length: 2),
        );

        expect(
          await getRecordFieldTypes(typeInstanceRef),
          ['bool', '(bool, int)'],
        );
      });
    });

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
      await onBreakPoint('printNestedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeInstanceRef =
            await getInstanceRef(frame, 'record.runtimeType');

        expect(
          await getUnwrappedTypeInstance(typeInstanceRef),
          matchRecordTypeInstance(length: 2),
        );

        expect(
          await getRecordFieldTypes(typeInstanceRef),
          ['bool', '(bool, int)'],
        );
      });
    });

    test('nested record type with named fields display', () async {
      await onBreakPoint('printNestedNamedLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final typeInstanceRef =
            await getInstanceRef(frame, 'record.runtimeType');
        final typeInstance = await getObject(typeInstanceRef.id!);
        final typeClassId = typeInstance.classRef!.id;

        expect(await getObject(typeClassId), matchTypeClass);

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
    });
  });
}
