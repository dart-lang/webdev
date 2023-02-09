// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/logging.dart';

class TestSetup {
  TestContext context;

  TestSetup.sound()
      : context = TestContext.withSoundNullSafety(
          packageName: '_experimentSound',
          webAssetsPath: 'web',
          dartEntryFileName: 'main.dart',
          htmlEntryFileName: 'index.html',
        );

  ChromeProxyService get service =>
      fetchChromeProxyService(context.debugConnection);
}

void main() async {
  // Enable verbose logging for debugging.
  final debug = false;

  for (var compilationMode in CompilationMode.values) {
    await _runTests(
      compilationMode: compilationMode,
      debug: debug,
    );
  }
}

Future<void> _runTests({
  required CompilationMode compilationMode,
  required bool debug,
}) async {
  final setup = TestSetup.sound();
  final context = setup.context;
  late VmServiceInterface service;
  late Stream<Event> stream;
  late String isolateId;
  late ScriptRef mainScript;

  onBreakPoint(breakPointId, body) =>
      _onBreakPoint(setup, stream, isolateId, mainScript, breakPointId, body);

  getInstance(frame, expression) =>
      _getInstance(service, isolateId, frame, expression);

  getObject(instanceId) => service.getObject(isolateId, instanceId);

  getInstanceRef(frame, expression) =>
      _getInstanceRef(service, isolateId, frame, expression);

  getFields(instanceRef, {offset, count}) =>
      _getFields(service, isolateId, instanceRef, offset: offset, count: count);

  group('$compilationMode |', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        compilationMode: compilationMode,
        enableExpressionEvaluation: true,
        verboseCompiler: debug,
        experiments: ['records'],
      );
      service = setup.service;

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

    test('simple records', () async {
      await onBreakPoint('printSimpleLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(await getObject(instanceId),
            _matchRecordInstance(length: 2, type: 'RecordType(bool, int)'));

        expect(await getFields(instanceRef), {'1': 'true', '2': '3'});
        expect(
            await getFields(instanceRef, offset: 0), {'1': 'true', '2': '3'});
        expect(await getFields(instanceRef, offset: 1), {'2': '3'});
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(
            await getFields(instanceRef, offset: 0, count: 1), {'1': 'true'});
        expect(await getFields(instanceRef, offset: 0, count: 2),
            {'1': 'true', '2': '3'});
        expect(await getFields(instanceRef, offset: 0, count: 5),
            {'1': 'true', '2': '3'});
        expect(await getFields(instanceRef, offset: 2, count: 5), {});
      });
    });

    test('simple records, field access', () async {
      await onBreakPoint('printSimpleLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            _matchPrimitiveInstance(kind: InstanceKind.kBool, value: 'true'));

        expect(await getInstance(frame, r'record.$2'),
            _matchPrimitiveInstance(kind: InstanceKind.kDouble, value: '3'));
      });
    });

    test('simple records with named fields', () async {
      await onBreakPoint('printSimpleNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;

        expect(
            await getObject(instanceId),
            _matchRecordInstance(
                length: 2, type: 'RecordType(bool, {String cat})'));

        expect(await getFields(instanceRef), {'1': 'true', 'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 0),
            {'1': 'true', 'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 1), {'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(
            await getFields(instanceRef, offset: 0, count: 1), {'1': 'true'});
        expect(await getFields(instanceRef, offset: 0, count: 2),
            {'1': 'true', 'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 0, count: 5),
            {'1': 'true', 'cat': 'Vasya'});
        expect(await getFields(instanceRef, offset: 2, count: 5), {});
      });
    });

    test('simple records with named fields, field access', () async {
      await onBreakPoint('printSimpleNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            _matchPrimitiveInstance(kind: InstanceKind.kBool, value: 'true'));

        expect(
            await getInstance(frame, r'record.cat'),
            _matchPrimitiveInstance(
                kind: InstanceKind.kString, value: 'Vasya'));
      });
    });

    test('complex records fields', () async {
      await onBreakPoint('printComplexLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            _matchRecordInstance(
                length: 3,
                type: 'RecordType(bool, int, IdentityMap<String, int>)'));

        expect(await getFields(instanceRef), {
          '1': 'true',
          '2': '3',
          '3': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 0), {
          '1': 'true',
          '2': '3',
          '3': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 1), {
          '2': '3',
          '3': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 1, count: 1), {'2': '3'});
        expect(await getFields(instanceRef, offset: 1, count: 2), {
          '2': '3',
          '3': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 2), {
          '3': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 3), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(
            await getFields(instanceRef, offset: 0, count: 1), {'1': 'true'});
        expect(await getFields(instanceRef, offset: 0, count: 2),
            {'1': 'true', '2': '3'});
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          '1': 'true',
          '2': '3',
          '3': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 3, count: 5), {});
      });
    });

    test('complex records, field access', () async {
      await onBreakPoint('printComplexLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            _matchPrimitiveInstance(kind: InstanceKind.kBool, value: 'true'));

        expect(await getInstance(frame, r'record.$2'),
            _matchPrimitiveInstance(kind: InstanceKind.kDouble, value: '3'));

        final third = await getInstanceRef(frame, r'record.$3');
        expect(third.kind, InstanceKind.kMap);
        expect(await getFields(third), {'a': '1', 'b': '5'});
      });
    });

    test('complex records with named fields', () async {
      await onBreakPoint('printComplexNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            _matchRecordInstance(
                length: 3,
                type:
                    'RecordType(bool, int, {IdentityMap<String, int> array})'));

        expect(await getFields(instanceRef), {
          '1': 'true',
          '2': '3',
          'array': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 0), {
          '1': 'true',
          '2': '3',
          'array': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 1), {
          '2': '3',
          'array': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 1, count: 1), {'2': '3'});
        expect(await getFields(instanceRef, offset: 1, count: 2), {
          '2': '3',
          'array': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 2), {
          'array': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 3), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(
            await getFields(instanceRef, offset: 0, count: 1), {'1': 'true'});
        expect(await getFields(instanceRef, offset: 0, count: 2),
            {'1': 'true', '2': '3'});
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          '1': 'true',
          '2': '3',
          'array': {'a': '1', 'b': '5'}
        });
        expect(await getFields(instanceRef, offset: 3, count: 5), {});
      });
    });

    test('complex records with named fields, field access', () async {
      await onBreakPoint('printComplexNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        expect(await getInstance(frame, r'record.$1'),
            _matchPrimitiveInstance(kind: InstanceKind.kBool, value: 'true'));

        expect(await getInstance(frame, r'record.$2'),
            _matchPrimitiveInstance(kind: InstanceKind.kDouble, value: '3'));

        final third = await getInstanceRef(frame, r'record.array');
        expect(third.kind, InstanceKind.kMap);
        expect(await getFields(third), {'a': '1', 'b': '5'});
      });
    });

    test('nested records', () async {
      await onBreakPoint('printNestedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            _matchRecordInstance(
                length: 2, type: 'RecordType(bool, RecordType(bool, int))'));

        expect(await getFields(instanceRef), {
          '1': 'true',
          '2': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 0), {
          '1': 'true',
          '2': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 1), {
          '2': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(
            await getFields(instanceRef, offset: 0, count: 1), {'1': 'true'});
        expect(await getFields(instanceRef, offset: 0, count: 2), {
          '1': 'true',
          '2': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          '1': 'true',
          '2': {'1': 'false', '2': '5'}
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
            _matchRecordInstance(length: 2, type: 'RecordType(bool, int)'));

        expect(await getFields(instanceRef), {'1': 'false', '2': '5'});
        expect(
            await getFields(instanceRef, offset: 0), {'1': 'false', '2': '5'});
      });
    });

    test('nested records with named fields,', () async {
      await onBreakPoint('printNestedNamedLocal', (event) async {
        final frame = event.topFrame!.index!;
        final instanceRef = await getInstanceRef(frame, 'record');

        final instanceId = instanceRef.id!;
        expect(
            await getObject(instanceId),
            _matchRecordInstance(
                length: 2,
                type: 'RecordType(bool, {RecordType(bool, int) inner})'));

        expect(await getFields(instanceRef), {
          '1': 'true',
          'inner': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 0), {
          '1': 'true',
          'inner': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 1), {
          'inner': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 1, count: 1), {
          'inner': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 1, count: 2), {
          'inner': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 2), {});
        expect(await getFields(instanceRef, offset: 0, count: 0), {});
        expect(
            await getFields(instanceRef, offset: 0, count: 1), {'1': 'true'});
        expect(await getFields(instanceRef, offset: 0, count: 2), {
          '1': 'true',
          'inner': {'1': 'false', '2': '5'}
        });
        expect(await getFields(instanceRef, offset: 0, count: 5), {
          '1': 'true',
          'inner': {'1': 'false', '2': '5'}
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
            _matchRecordInstance(length: 2, type: 'RecordType(bool, int)'));

        expect(await getFields(instanceRef), {'1': 'false', '2': '5'});
        expect(
            await getFields(instanceRef, offset: 0), {'1': 'false', '2': '5'});
      });
    });
  });
}

Future<void> _onBreakPoint(
  TestSetup setup,
  Stream<Event> stream,
  String isolateId,
  ScriptRef script,
  String breakPointId,
  Future<void> Function(Event event) body,
) async {
  final context = setup.context;
  final service = setup.service;

  Breakpoint? bp;
  try {
    final line =
        await context.findBreakpointLine(breakPointId, isolateId, script);
    bp = await service.addBreakpointWithScriptUri(isolateId, script.uri!, line);

    final event =
        await stream.firstWhere((e) => e.kind == EventKind.kPauseBreakpoint);

    await body(event);
  } finally {
    // Remove breakpoint so it doesn't impact other tests or retries.
    if (bp != null) {
      await service.removeBreakpoint(isolateId, bp.id!);
    }
  }
}

Future<Map<String, Object?>> _getFields(
  VmServiceInterface service,
  String isolateId,
  InstanceRef instanceRef, {
  int? offset,
  int? count,
}) async {
  final instanceId = instanceRef.id!;
  final instanceKind = instanceRef.kind;

  final result = await service.getObject(
    isolateId,
    instanceId,
    offset: offset,
    count: count,
  );

  expect(result, isA<Instance>());
  final instance = result as Instance;
  expect(instance.kind, instanceKind);

  final fields = instance.fields;
  final associations = instance.associations;

  Map<String, InstanceRef>? fieldRefs;
  if (fields != null) {
    fieldRefs = _boundFieldsToMap(fields);
  } else if (associations != null) {
    fieldRefs = _associationsToMap(associations);
  } else {
    fieldRefs = {};
  }

  final fieldValues = <String, Object?>{};
  for (var p in fieldRefs.entries) {
    fieldValues[p.key] =
        p.value.valueAsString ?? await _getFields(service, isolateId, p.value);
  }
  return fieldValues;
}

Future<InstanceRef> _getInstanceRef(
  VmServiceInterface service,
  String isolateId,
  int frame,
  String expression,
) async {
  final result = await service.evaluateInFrame(
    isolateId,
    frame,
    expression,
  );
  expect(result, isA<InstanceRef>());
  return result as InstanceRef;
}

Future<Instance> _getInstance(
  VmServiceInterface service,
  String isolateId,
  int frame,
  String expression,
) async {
  final instanceRef = await _getInstanceRef(
    service,
    isolateId,
    frame,
    expression,
  );

  expect(instanceRef.id, isNotNull);
  final result = await service.getObject(
    isolateId,
    instanceRef.id!,
  );

  expect(result, isA<Instance>());
  return result as Instance;
}

Map<String, InstanceRef> _associationsToMap(
        Iterable<MapAssociation> associations) =>
    Map.fromEntries(
        associations.map((e) => MapEntry(e.key.valueAsString, e.value)));

Map<String, InstanceRef> _boundFieldsToMap(Iterable<BoundField> fields) =>
    Map.fromEntries(fields
        .where((e) => e.name != null)
        .map((e) => MapEntry(e.name, e.value)));

Matcher _matchPrimitiveInstance(
        {required String kind, required dynamic value}) =>
    isA<Instance>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.valueAsString, 'value', value);

Matcher _matchRecordInstance({required int length, required String type}) =>
    isA<Instance>()
        .having((e) => e.kind, 'kind', InstanceKind.kRecord)
        .having((e) => e.length, 'length', length)
        .having((e) => e.classRef!.name, 'classRef.name', type);
