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

    final fieldValues = <dynamic, Object?>{};
    for (var p in fieldRefs.entries) {
      fieldValues[p.key] =
          _getValue(p.value) ?? await getFields(isolateId, p.value);
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
    .having((e) => e.classRef!, 'classRef', matchRecordType);

Matcher matchRecordClass = matchClass(libraryId: 'dart:core', type: 'Record');

Matcher matchTypeClass = matchClass(libraryId: 'dart:_runtime', type: '_Type');

Matcher matchClass({required String libraryId, required String type}) =>
    isA<Class>()
        .having((e) => e.name, 'name', type)
        .having((e) => e.id, 'id', classIdFor(libraryId, type));

Matcher matchRecordType = matchType('Record');

Matcher matchType(String type) =>
    isA<ClassRef>().having((e) => e.name, 'type name', type);

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
