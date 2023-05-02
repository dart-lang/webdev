// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
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

  getDisplayedRef(instanceId) =>
      testInspector.getDisplayedRef(isolateId, instanceId);

  getDisplayedFields(instanceRef) =>
      testInspector.getDisplayedFields(isolateId, instanceRef);

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

  final matchTypeObject = {
    'hashCode': matchPrimitiveInstanceRef(kind: InstanceKind.kDouble),
    'runtimeType': matchTypeInstanceRef,
  };

  final matchDisplayedTypeObject = [
    matches('[0-9]*'),
    'Type',
  ];

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

    test('String type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, "'1'.runtimeType");
        final instanceId = instanceRef.id!;

        final instance = await getObject(instanceId);
        expect(instance, matchTypeInstance);

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchTypeClass);
        expect(await getFields(instanceRef, depth: 1), matchTypeObject);
      });
    });

    test('String type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, "'1'.runtimeType");
        final instanceId = instanceRef.id!;
        final displayedRef = await getDisplayedRef(instanceId);
        final displayedInstance = await getObject(displayedRef.id);

        expect(displayedInstance, matchTypeStringInstance('String'));
        expect(await getDisplayedFields(instanceRef), matchDisplayedTypeObject);
      });
    });

    test('int type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, '1.runtimeType');
        final instanceId = instanceRef.id!;

        final instance = await getObject(instanceId);
        expect(instance, matchTypeInstance);

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchTypeClass);
        expect(await getFields(instanceRef, depth: 1), matchTypeObject);
      });
    });

    test('int type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, '1.runtimeType');
        final instanceId = instanceRef.id!;

        final displayedRef = await getDisplayedRef(instanceId);
        final displayedInstance = await getObject(displayedRef.id);

        expect(displayedInstance, matchTypeStringInstance('int'));
        expect(await getDisplayedFields(instanceRef), matchDisplayedTypeObject);
      });
    });

    test('list type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, '<int>[].runtimeType');
        final instanceId = instanceRef.id!;

        final instance = await getObject(instanceId);
        expect(instance, matchTypeInstance);

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchTypeClass);
        expect(await getFields(instanceRef, depth: 1), matchTypeObject);
      });
    });

    test('list type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, '<int>[].runtimeType');
        final instanceId = instanceRef.id!;

        final displayedRef = await getDisplayedRef(instanceId);
        final displayedInstance = await getObject(displayedRef.id);

        expect(displayedInstance, matchTypeStringInstance('List<int>'));
        expect(await getDisplayedFields(instanceRef), matchDisplayedTypeObject);
      });
    });

    test('map type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef =
            await getInstanceRef(frame, '<int, String>{}.runtimeType');
        final instanceId = instanceRef.id!;

        final instance = await getObject(instanceId);
        expect(instance, matchTypeInstance);

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchTypeClass);
        expect(await getFields(instanceRef, depth: 1), matchTypeObject);
      });
    });

    test('map type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef =
            await getInstanceRef(frame, '<int, String>{}.runtimeType');
        final instanceId = instanceRef.id!;

        final displayedRef = await getDisplayedRef(instanceId);
        final displayedInstance = await getObject(displayedRef.id);

        expect(
          displayedInstance,
          matchTypeStringInstance('IdentityMap<int, String>'),
        );
        expect(await getDisplayedFields(instanceRef), matchDisplayedTypeObject);
      });
    });

    test('set type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, '<int>{}.runtimeType');
        final instanceId = instanceRef.id!;

        final instance = await getObject(instanceId);
        expect(instance, matchTypeInstance);

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchTypeClass);
        expect(await getFields(instanceRef, depth: 1), matchTypeObject);
      });
    });

    test('set type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, '<int>{}.runtimeType');
        final instanceId = instanceRef.id!;

        final displayedRef = await getDisplayedRef(instanceId);
        final displayedInstance = await getObject(displayedRef.id);

        expect(
          displayedInstance,
          matchTypeStringInstance('_IdentityHashSet<int>'),
        );
        expect(await getDisplayedFields(instanceRef), matchDisplayedTypeObject);
      });
    });

    test('record type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, "(0,'a').runtimeType");
        final instanceId = instanceRef.id!;

        final instance = await getObject(instanceId);
        expect(instance, matchRecordTypeInstance(length: 2));

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchRecordTypeClass);
        expect(
          await getFields(instanceRef, depth: 2),
          {1: matchTypeObject, 2: matchTypeObject},
        );
      });
    });

    test('record type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, "(0,'a').runtimeType");
        final instanceId = instanceRef.id!;

        final displayedRef = await getDisplayedRef(instanceId);
        final displayedInstance = await getObject(displayedRef.id);

        expect(
          displayedInstance,
          matchTypeStringInstance('(int, String)'),
        );
        expect(
          await getDisplayedFields(instanceRef),
          ['int', 'String'],
        );
      });
    });

    test('class type', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef =
            await getInstanceRef(frame, "Uri.file('').runtimeType");
        final instanceId = instanceRef.id!;

        final instance = await getObject(instanceId);
        expect(instance, matchTypeInstance);

        final classId = instanceRef.classRef!.id;
        expect(await getObject(classId), matchTypeClass);
        expect(await getFields(instanceRef, depth: 1), matchTypeObject);
      });
    });

    test('class type display', () async {
      await onBreakPoint('printSimpleLocalRecord', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef =
            await getInstanceRef(frame, "Uri.file('').runtimeType");
        final instanceId = instanceRef.id!;

        final displayedRef = await getDisplayedRef(instanceId);
        final displayedInstance = await getObject(displayedRef.id);

        expect(displayedInstance, matchTypeStringInstance('_Uri'));
        expect(await getDisplayedFields(instanceRef), matchDisplayedTypeObject);
      });
    });
  });
}
