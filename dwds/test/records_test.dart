// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/logging.dart';

class TestSetup {
  TestContext context;

  TestSetup.sound()
      : context = TestContext.withSoundNullSafety(
          packageName: '_experiment',
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

  final setup = TestSetup.sound();
  final context = setup.context;
  late Stream<Event> stream;
  late VmServiceInterface service;

  Future<void> onBreakPoint(
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
          isolateId, script.uri!, line);

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

  // Remove once the dev version below is released.
  final recordsIndexStartsFromZero =
      semver.Version.parse(Platform.version.split(' ').first) >=
          semver.Version.parse('3.0.0-180.0.dev');

  // Remove once the dev version below is released.
  final recordTypesWork = !recordsIndexStartsFromZero ||
      semver.Version.parse(Platform.version.split(' ').first) >=
          semver.Version.parse('3.0.0-188.0.dev');

  for (var compilationMode in CompilationMode.values) {
    group('$compilationMode |', () {
      setUpAll(() async {
        setCurrentLogWriter(debug: debug);
      });

      group('shared context |', () {
        setUpAll(() async {
          setCurrentLogWriter(debug: debug);
          await context.setUp(
            compilationMode: compilationMode,
            enableExpressionEvaluation: true,
            verboseCompiler: debug,
            experiments: ['records'],
          );
          service = setup.service;
        });

        tearDownAll(() async {
          await context.tearDown();
        });

        setUp(() => setCurrentLogWriter(debug: debug));

        group('evaluateInFrame |', () {
          late String isolateId;
          late ScriptRef mainScript;

          setUp(() async {
            setCurrentLogWriter(debug: debug);
            final vm = await service.getVM();
            isolateId = vm.isolates!.first.id!;
            final scripts = await service.getScripts(isolateId);

            await service.streamListen('Debug');
            stream = service.onEvent('Debug');

            mainScript = scripts.scripts!
                .firstWhere((each) => each.uri!.contains('main.dart'));
          });

          tearDown(() async {
            await service.resume(isolateId);
          });

          test('can evaluate and display simple records', () async {
            await onBreakPoint(isolateId, mainScript, 'printSimpleLocal',
                (event) async {
              final instanceRef = await _getInstanceRef(
                service,
                isolateId,
                event.topFrame!.index!,
                'record',
              );

              if (recordTypesWork) {
                final instanceId = instanceRef.id!;
                expect(
                    await service.getObject(isolateId, instanceId),
                    _matchRecordInstance(
                        length: 2, type: 'RecordType(bool, int)'));
              }

              expect(
                await _getFields(service, isolateId, instanceRef),
                {'0': 'true', '1': '3'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef, offset: 0),
                {'0': 'true', '1': '3'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef, offset: 1),
                {'1': '3'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 0),
                {},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 1),
                {'0': 'true'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 2),
                {'0': 'true', '1': '3'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 5),
                {'0': 'true', '1': '3'},
              );
            });
          });

          test('can evaluate and display simple records fields', () async {
            await onBreakPoint(isolateId, mainScript, 'printSimpleLocal',
                (event) async {
              final frame = event.topFrame!.index!;
              expect(
                  await _getInstance(service, isolateId, frame, r'record.$1'),
                  _matchPrimitiveInstance(
                      kind: InstanceKind.kBool, value: 'true'));
              expect(
                  await _getInstance(service, isolateId, frame, r'record.$2'),
                  _matchPrimitiveInstance(
                      kind: InstanceKind.kDouble, value: '3'));
            });
          }, skip: !recordsIndexStartsFromZero);

          test('can evaluate and display complex records', () async {
            await onBreakPoint(isolateId, mainScript, 'printComplexLocal',
                (event) async {
              final instanceRef = await _getInstanceRef(
                service,
                isolateId,
                event.topFrame!.index!,
                'record',
              );

              if (recordTypesWork) {
                final instanceId = instanceRef.id!;
                expect(
                    await service.getObject(isolateId, instanceId),
                    _matchRecordInstance(
                        length: 3,
                        type:
                            'RecordType(bool, int, IdentityMap<String, int>)'));
              }

              expect(instanceRef.kind, InstanceKind.kRecord);
              expect(instanceRef.length, 3);

              expect(
                await _getFields(service, isolateId, instanceRef),
                {
                  '0': 'true',
                  '1': '3',
                  '2': {'a': '1', 'b': '5'}
                },
              );
              expect(
                await _getFields(service, isolateId, instanceRef, offset: 0),
                {
                  '0': 'true',
                  '1': '3',
                  '2': {'a': '1', 'b': '5'}
                },
              );
              expect(
                await _getFields(service, isolateId, instanceRef, offset: 1),
                {
                  '1': '3',
                  '2': {'a': '1', 'b': '5'}
                },
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 0),
                {},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 1),
                {'0': 'true'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 2),
                {'0': 'true', '1': '3'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 5),
                {
                  '0': 'true',
                  '1': '3',
                  '2': {'a': '1', 'b': '5'}
                },
              );
            });
          });

          test('can evaluate and display complex records fields', () async {
            await onBreakPoint(isolateId, mainScript, 'printComplexLocal',
                (event) async {
              final frame = event.topFrame!.index!;
              expect(
                  await _getInstance(service, isolateId, frame, r'record.$1'),
                  _matchPrimitiveInstance(
                      kind: InstanceKind.kBool, value: 'true'));

              expect(
                  await _getInstance(service, isolateId, frame, r'record.$2'),
                  _matchPrimitiveInstance(
                      kind: InstanceKind.kDouble, value: '3'));

              final third = await _getInstanceRef(
                  service, isolateId, frame, r'record.$3');
              expect(third.kind, InstanceKind.kMap);
              expect(
                await _getFields(service, isolateId, third),
                {'a': '1', 'b': '5'},
              );
            });
          }, skip: !recordsIndexStartsFromZero);

          test('can evaluate and display nested records', () async {
            await onBreakPoint(isolateId, mainScript, 'printNestedLocal',
                (event) async {
              final instanceRef = await _getInstanceRef(
                service,
                isolateId,
                event.topFrame!.index!,
                'record',
              );

              if (recordTypesWork) {
                final instanceId = instanceRef.id!;
                expect(
                    await service.getObject(isolateId, instanceId),
                    _matchRecordInstance(
                        length: 2,
                        type: 'RecordType(bool, RecordType(bool, int))'));
              }

              expect(
                await _getFields(service, isolateId, instanceRef),
                {
                  '0': 'true',
                  '1': {'0': 'false', '1': '5'}
                },
              );
              expect(
                await _getFields(service, isolateId, instanceRef, offset: 0),
                {
                  '0': 'true',
                  '1': {'0': 'false', '1': '5'}
                },
              );
              expect(
                await _getFields(service, isolateId, instanceRef, offset: 1),
                {
                  '1': {'0': 'false', '1': '5'}
                },
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 0),
                {},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 1),
                {'0': 'true'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 2),
                {
                  '0': 'true',
                  '1': {'0': 'false', '1': '5'}
                },
              );
              expect(
                await _getFields(service, isolateId, instanceRef,
                    offset: 0, count: 5),
                {
                  '0': 'true',
                  '1': {'0': 'false', '1': '5'}
                },
              );
            });
          });

          test('can evaluate and display nested records fields', () async {
            await onBreakPoint(isolateId, mainScript, 'printNestedLocal',
                (event) async {
              final instanceRef = await _getInstanceRef(
                service,
                isolateId,
                event.topFrame!.index!,
                r'record.$2',
              );

              if (recordTypesWork) {
                final instanceId = instanceRef.id!;
                expect(
                    await service.getObject(isolateId, instanceId),
                    _matchRecordInstance(
                        length: 2, type: 'RecordType(bool, int)'));
              }

              expect(
                await _getFields(service, isolateId, instanceRef),
                {'0': 'false', '1': '5'},
              );
              expect(
                await _getFields(service, isolateId, instanceRef, offset: 0),
                {'0': 'false', '1': '5'},
              );
            });
          }, skip: !recordsIndexStartsFromZero);
        });
      });
    });
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
