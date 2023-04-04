// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'package:dwds/src/debugging/metadata/class.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../fixtures/context.dart';

class TestInspector {
  TestInspector(this.context);
  TestContext context;

  VmServiceInterface get service => context.debugConnection.vmService;

  Future<void> onBreakPoint(
    Stream<Event> stream,
    String isolateId,
    ScriptRef script,
    String breakPointId,
    Future<void> Function(Event event) body,
  ) async {
    Breakpoint? bp;
    try {
      final line =
          await context.findBreakpointLine(breakPointId, isolateId, script);
      bp = await service.addBreakpointWithScriptUri(
        isolateId,
        script.uri!,
        line,
      );

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

  Future<dynamic> getFields(
    String isolateId,
    InstanceRef instanceRef, {
    int? offset,
    int? count,
    int depth = -1,
  }) async {
    final instanceId = instanceRef.id!;

    final result = await service.getObject(
      isolateId,
      instanceId,
      offset: offset,
      count: count,
    );

    expect(result, isA<Instance>());
    final instance = result as Instance;

    // TODO(annagrin): we sometimes get mismatching reference
    // and instance kinds from chrome. Investigate.
    if (instanceRef.kind != InstanceKind.kClosure) {
      expect(
        instance.kind,
        instanceRef.kind,
        reason: 'object $instanceId with ref kind ${instanceRef.kind} '
            'has an instance kind ${instance.kind}',
      );
    }

    final fields = instance.fields;
    final associations = instance.associations;
    final elements = instance.elements;

    Map<dynamic, InstanceRef>? fieldRefs;
    if (fields != null) {
      fieldRefs = _boundFieldsToMap(fields);
    } else if (associations != null) {
      fieldRefs = _associationsToMap(associations);
    } else if (elements != null) {
      fieldRefs = _elementsToMap(elements);
    } else {
      fieldRefs = {};
    }

    if (depth > 0) {
      depth--;
    }
    if (depth == 0) {
      return elements == null ? fieldRefs : fieldRefs.values.toList();
    }

    final fieldValues = <dynamic, Object?>{};
    for (var p in fieldRefs.entries) {
      fieldValues[p.key] = _getValue(p.value) ??
          await getFields(
            isolateId,
            p.value,
            depth: depth,
          );
    }
    return elements == null ? fieldValues : fieldValues.values.toList();
  }

  Future<InstanceRef> getInstanceRef(
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

  Future<Instance> getInstance(
    String isolateId,
    int frame,
    String expression,
  ) async {
    final instanceRef = await getInstanceRef(
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

  Future<Map<String?, Instance?>> getFrameVariables(
    String isolateId,
    Frame frame,
  ) async {
    final refs = <String, InstanceRef>{
      for (var variable in frame.vars!)
        variable.name!: variable.value as InstanceRef
    };
    final instances = <String, Instance>{};
    for (final p in refs.entries) {
      instances[p.key] =
          await service.getObject(isolateId, p.value.id!) as Instance;
    }
    return instances;
  }

  Future<InstanceRef> getUnwrappedTypeInstanceRef(
    String isolateId,
    InstanceRef ref,
  ) async {
    final typeClassId = ref.classRef!.id!;

    // `o.runtimeType` is an instance of `Type`.
    expect(await service.getObject(isolateId, typeClassId), matchTypeClass);

    // Get `o.runtimeType._type`.
    return (await getFields(isolateId, ref, depth: 1)
        as Map<dynamic, Object?>)['_type'] as InstanceRef;
  }

  Future<Instance> getUnwrappedTypeInstance(
    String isolateId,
    InstanceRef ref,
  ) async {
    final typeInstanceRef = await getUnwrappedTypeInstanceRef(isolateId, ref);
    return await service.getObject(isolateId, typeInstanceRef.id!) as Instance;
  }

  Future<List<String?>> getFieldTypes(
    String isolateId,
    InstanceRef ref,
  ) async {
    final fieldTypeInstanceRefs =
        await getFields(isolateId, ref, depth: 1) as Map<dynamic, InstanceRef>;

    final fieldTypes = await Future.wait(
      fieldTypeInstanceRefs.values.map(
        (ref) async => await service.invoke(isolateId, ref.id!, 'toString', []),
      ),
    );
    return fieldTypes.map((ref) => (ref as InstanceRef).valueAsString).toList();
  }
}

Map<String, InstanceRef> _associationsToMap(
  Iterable<MapAssociation> associations,
) =>
    Map.fromEntries(
      associations.map((e) => MapEntry(e.key.valueAsString, e.value)),
    );

Map<dynamic, InstanceRef> _boundFieldsToMap(Iterable<BoundField> fields) =>
    Map.fromEntries(
      fields.where((e) => e.name != null).map((e) => MapEntry(e.name, e.value)),
    );

Map<dynamic, InstanceRef> _elementsToMap(List<dynamic> fields) =>
    Map.fromEntries(
      fields
          .where((e) => e != null)
          .map((e) => MapEntry(fields.indexOf(e), e!)),
    );

Matcher matchPrimitiveInstance({
  required String kind,
  required dynamic value,
}) =>
    isA<Instance>()
        .having((e) => e.kind, 'kind', kind)
        .having(_getValue, 'value', value);

Matcher matchPlainInstance({required String type}) => isA<Instance>()
    .having((e) => e.kind, 'kind', InstanceKind.kPlainInstance)
    .having((e) => e.classRef!.name, 'classRef.name', type);

Matcher matchListInstance({required String type}) => isA<Instance>()
    .having((e) => e.kind, 'kind', InstanceKind.kList)
    .having((e) => e.classRef!.name, 'classRef.name', type);

Matcher matchMapInstance({required String type}) => isA<Instance>()
    .having((e) => e.kind, 'kind', InstanceKind.kMap)
    .having((e) => e.classRef!.name, 'classRef.name', type);

Matcher matchSetInstance({required String type}) => isA<Instance>()
    .having((e) => e.kind, 'kind', InstanceKind.kSet)
    .having((e) => e.classRef!.name, 'classRef.name', type);

Matcher matchRecordInstance({required int length}) => isA<Instance>()
    .having((e) => e.kind, 'kind', InstanceKind.kRecord)
    .having((e) => e.length, 'length', length)
    .having((e) => e.classRef!, 'classRef', matchRecordClassRef);

Matcher matchRecordTypeInstance({required int length}) => isA<Instance>()
    .having((e) => e.kind, 'kind', InstanceKind.kRecordType)
    .having((e) => e.length, 'length', length)
    .having((e) => e.classRef!, 'classRef', matchRecordTypeClassRef);

Matcher matchTypeInstance = isA<Instance>()
    .having((e) => e.kind, 'kind', InstanceKind.kPlainInstance)
    .having((e) => e.classRef!.name, 'classRef.name', matchTypeClassRef);

Matcher matchRecordClass = matchClass(libraryId: 'dart:core', type: 'Record');
Matcher matchRecordTypeClass =
    matchClass(libraryId: 'dart:_runtime', type: 'RecordType');
Matcher matchTypeClass = matchClass(libraryId: 'dart:_runtime', type: '_Type');

Matcher matchClass({required String libraryId, required String type}) =>
    isA<Class>()
        .having((e) => e.name, 'name', type)
        .having((e) => e.id, 'id', classIdFor(libraryId, type));

Matcher matchRecordClassRef = matchClassRef('Record');
Matcher matchRecordTypeClassRef = matchClassRef('RecordType');
Matcher matchTypeClassRef = matchClassRef('Type');

Matcher matchClassRef(String type) =>
    isA<ClassRef>().having((e) => e.name, 'class name', type);

Object? _getValue(InstanceRef instanceRef) {
  switch (instanceRef.kind) {
    case InstanceKind.kBool:
      return instanceRef.valueAsString == 'true';
    case InstanceKind.kDouble:
    case InstanceKind.kInt:
      return double.parse(instanceRef.valueAsString!);
    case InstanceKind.kString:
      return instanceRef.valueAsString;
    default:
      return null;
  }
}
