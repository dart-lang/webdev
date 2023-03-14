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
      stream, isolateId, mainScript, breakPointId, body);

  getInstance(frame, expression) =>
      testInspector.getInstance(isolateId, frame, expression);

  getObject(instanceId) => service.getObject(isolateId, instanceId);

  getInstanceRef(frame, expression) =>
      testInspector.getInstanceRef(isolateId, frame, expression);

  getFields(instanceRef, {offset, count}) => testInspector
      .getFields(isolateId, instanceRef, offset: offset, count: count);

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

    tearDownAll(() async {
      await context.tearDown();
    });

    setUp(() => setCurrentLogWriter(debug: debug));
    tearDown(() => service.resume(isolateId));

    test('simple records', () async {
      await onBreakPoint('printSimpleLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(await getObject(instanceId),
            matchRecordInstance(length: 2, type: 'RecordType(bool, int)'));

        expect(await getFields(instanceRef), {1: true, 2: 3});
        expect(await getFields(instanceRef, offset: 0), {1: true, 2: 3});
        expect(await getFields(instanceRef, offset: 1), {2: 3});
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(await getFields(instanceRef, offset: 0, count: 1), {1: true});
        expect(
            await getFields(instanceRef, offset: 0, count: 2), {1: true, 2: 3});
        expect(
            await getFields(instanceRef, offset: 0, count: 5), {1: true, 2: 3});
        expect(await getFields(instanceRef, offset: 2, count: 5), {});
      });
    });

    test('simple records, field access', () async {
      await onBreakPoint('printSimpleLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            matchPrimitiveInstance(kind: InstanceKind.kBool, value: true));

        expect(await getInstance(frame, r'record.$2'),
            matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 3));
      });
    });

    test('simple records with named fields', () async {
      await onBreakPoint('printSimpleNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;

        expect(
            await getObject(instanceId),
            matchRecordInstance(
                length: 2, type: 'RecordType(bool, {String cat})'));

        expect(await getFields(instanceRef), {1: true, 'cat': 'Vasya'});
        expect(
            await getFields(instanceRef, offset: 0), {1: true, 'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 1), {'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(await getFields(instanceRef, offset: 0, count: 1), {1: true});
        expect(await getFields(instanceRef, offset: 0, count: 2),
            {1: true, 'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 0, count: 5),
            {1: true, 'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 2, count: 5), {});
      });
    });

    test('simple records with named fields, field access', () async {
      await onBreakPoint('printSimpleNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            matchPrimitiveInstance(kind: InstanceKind.kBool, value: true));

        expect(await getInstance(frame, r'record.cat'),
            matchPrimitiveInstance(kind: InstanceKind.kString, value: 'Vasya'));
      });
    });

    test('complex records fields', () async {
      await onBreakPoint('printComplexLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            matchRecordInstance(
                length: 3,
                type: 'RecordType(bool, int, IdentityMap<String, int>)'));

        expect(await getFields(instanceRef), {
          1: true,
          2: 3,
          3: {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 0), {
          1: true,
          2: 3,
          3: {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 1), {
          2: 3,
          3: {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 1, count: 1), {2: 3});
        expect(await getFields(instanceRef, offset: 1, count: 2), {
          2: 3,
          3: {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 2), {
          3: {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 3), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(await getFields(instanceRef, offset: 0, count: 1), {1: true});
        expect(
            await getFields(instanceRef, offset: 0, count: 2), {1: true, 2: 3});
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          1: true,
          2: 3,
          3: {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 3, count: 5), {});
      });
    });

    test('complex records, field access', () async {
      await onBreakPoint('printComplexLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            matchPrimitiveInstance(kind: InstanceKind.kBool, value: true));

        expect(await getInstance(frame, r'record.$2'),
            matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 3));

        final third = await getInstanceRef(frame, r'record.$3');
        expect(third.kind, InstanceKind.kMap);
        expect(await getFields(third), {'a': 1, 'b': 5});
      });
    });

    test('complex records with named fields', () async {
      await onBreakPoint('printComplexNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            matchRecordInstance(
                length: 3,
                type:
                    'RecordType(bool, int, {IdentityMap<String, int> array})'));

        expect(await getFields(instanceRef), {
          1: true,
          2: 3,
          'array': {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 0), {
          1: true,
          2: 3,
          'array': {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 1), {
          2: 3,
          'array': {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 1, count: 1), {2: 3});
        expect(await getFields(instanceRef, offset: 1, count: 2), {
          2: 3,
          'array': {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 2), {
          'array': {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 3), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(await getFields(instanceRef, offset: 0, count: 1), {1: true});
        expect(
            await getFields(instanceRef, offset: 0, count: 2), {1: true, 2: 3});
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          1: true,
          2: 3,
          'array': {'a': 1, 'b': 5}
        });
        expect(await getFields(instanceRef, offset: 3, count: 5), {});
      });
    });

    test('complex records with named fields, field access', () async {
      await onBreakPoint('printComplexNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            matchPrimitiveInstance(kind: InstanceKind.kBool, value: true));

        expect(await getInstance(frame, r'record.$2'),
            matchPrimitiveInstance(kind: InstanceKind.kDouble, value: 3));

        final third = await getInstanceRef(frame, r'record.array');
        expect(third.kind, InstanceKind.kMap);
        expect(await getFields(third), {'a': 1, 'b': 5});
      });
    });

    test('nested records', () async {
      await onBreakPoint('printNestedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            matchRecordInstance(
                length: 2, type: 'RecordType(bool, RecordType(bool, int))'));

        expect(await getFields(instanceRef), {
          1: true,
          2: {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 0), {
          1: true,
          2: {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 1), {
          2: {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(await getFields(instanceRef, offset: 0, count: 1), {1: true});
        expect(await getFields(instanceRef, offset: 0, count: 2), {
          1: true,
          2: {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          1: true,
          2: {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 2, count: 5), {});
      });
    });

    test('nested records, field access', () async {
      await onBreakPoint('printNestedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, r'record.$2');

        final instanceId = instanceRef.id!;
        expect(await getObject(instanceId),
            matchRecordInstance(length: 2, type: 'RecordType(bool, int)'));

        expect(await getFields(instanceRef), {1: false, 2: 5});
        expect(await getFields(instanceRef, offset: 0), {1: false, 2: 5});
      });
    });

    test('nested records with named fields,', () async {
      await onBreakPoint('printNestedNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            matchRecordInstance(
                length: 2,
                type: 'RecordType(bool, {RecordType(bool, int) inner})'));

        expect(await getFields(instanceRef), {
          1: true,
          'inner': {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 0), {
          1: true,
          'inner': {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 1), {
          'inner': {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 1, count: 1), {
          'inner': {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 1, count: 2), {
          'inner': {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(await getFields(instanceRef, offset: 0, count: 1), {1: true});
        expect(await getFields(instanceRef, offset: 0, count: 2), {
          1: true,
          'inner': {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          1: true,
          'inner': {1: false, 2: 5}
        });
        expect(await getFields(instanceRef, offset: 2, count: 5), {});
      });
    });

    test('nested records with named fields, field access', () async {
      await onBreakPoint('printNestedNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, r'record.inner');

        final instanceId = instanceRef.id!;
        expect(await getObject(instanceId),
            matchRecordInstance(length: 2, type: 'RecordType(bool, int)'));

        expect(await getFields(instanceRef), {1: false, 2: 5});
        expect(await getFields(instanceRef, offset: 0), {1: false, 2: 5});
      });
    });
  }, skip: 'https://github.com/dart-lang/webdev/issues/2033');
}
