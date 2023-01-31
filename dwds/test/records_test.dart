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

  Future<void> onBreakPoint(String isolateId, ScriptRef script,
      String breakPointId, Future<void> Function() body) async {
    Breakpoint? bp;
    try {
      final line =
          await context.findBreakpointLine(breakPointId, isolateId, script);
      bp = await setup.service
          .addBreakpointWithScriptUri(isolateId, script.uri!, line);
      await body();
    } finally {
      // Remove breakpoint so it doesn't impact other tests or retries.
      if (bp != null) {
        await setup.service.removeBreakpoint(isolateId, bp.id!);
      }
    }
  }

  Future<Map<String, Object?>> getFields(
      String isolateId, InstanceRef instanceRef,
      {int? offset, int? count}) async {
    final instanceId = instanceRef.id!;
    final instanceKind = instanceRef.kind;

    final instance = await setup.service.getObject(isolateId, instanceId,
        offset: offset, count: count) as Instance;

    expect(instance.kind, instanceKind);

    final nameValues = <String, Object?>{};
    Map<Object, InstanceRef>? nameValueRefs;

    if (instance.fields != null) {
      nameValueRefs = Map.fromEntries(instance.fields!
          .where((e) => e.name != null)
          .map((e) => MapEntry(e.name, e.value)));
    } else if (instance.associations != null) {
      final keys = instance.associations!.map((e) => e.key as InstanceRef);
      final valueRefs =
          instance.associations!.map((e) => e.value as InstanceRef);

      nameValueRefs = Map.fromIterables(keys, valueRefs);
    }

    if (nameValueRefs != null) {
      for (var p in nameValueRefs.entries) {
        var key = p.key;
        key = key is String ? key : (key as InstanceRef).valueAsString!;
        nameValues[key] =
            p.value.valueAsString ?? await getFields(isolateId, p.value);
      }
    }
    return nameValues;
  }

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
        });

        tearDownAll(() async {
          await context.tearDown();
        });

        setUp(() => setCurrentLogWriter(debug: debug));

        group('evaluateInFrame |', () {
          late String isolateId;
          late ScriptRef mainScript;
          late Stream<Event> stream;

          setUp(() async {
            setCurrentLogWriter(debug: debug);
            final vm = await setup.service.getVM();
            isolateId = vm.isolates!.first.id!;
            final scripts = await setup.service.getScripts(isolateId);

            await setup.service.streamListen('Debug');
            stream = setup.service.onEvent('Debug');

            mainScript = scripts.scripts!
                .firstWhere((each) => each.uri!.contains('main.dart'));
          });

          tearDown(() async {
            await setup.service.resume(isolateId);
          });

          test('can evaluate and display simple records', () async {
            await onBreakPoint(isolateId, mainScript, 'printSimpleLocal',
                () async {
              final event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              final result = await setup.service
                  .evaluateInFrame(isolateId, event.topFrame!.index!, 'record');
              expect(result, isA<InstanceRef>());

              final instanceRef = result as InstanceRef;
              expect(instanceRef.id, isNotNull);
              expect(instanceRef.kind, InstanceKind.kRecord);
              expect(instanceRef.length, 2);

              expect(await getFields(isolateId, instanceRef),
                  {'0': 'true', '1': '3'});
              expect(await getFields(isolateId, instanceRef, offset: 0),
                  {'0': 'true', '1': '3'});
              expect(await getFields(isolateId, instanceRef, offset: 1),
                  {'1': '3'});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 0),
                  {});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 1),
                  {'0': 'true'});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 2),
                  {'0': 'true', '1': '3'});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 5),
                  {'0': 'true', '1': '3'});
            });
          });

          test('can evaluate and display simple records fields', () async {
            await onBreakPoint(isolateId, mainScript, 'printSimpleLocal',
                () async {
              final event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              final result = await setup.service.evaluateInFrame(
                  isolateId, event.topFrame!.index!, r'record.$1');
              expect(result, isA<InstanceRef>());

              final instanceRef = result as InstanceRef;
              expect(instanceRef.id, isNotNull);

              final instanceId = instanceRef.id!;
              final instance =
                  await setup.service.getObject(isolateId, instanceId);

              expect(
                  instance,
                  isA<Instance>()
                      .having((e) => e.kind, 'kind', InstanceKind.kDouble)
                      .having((e) => e.valueAsString, 'valueAsString', '3'));
            });
          });

          test('can evaluate and display complex records', () async {
            await onBreakPoint(isolateId, mainScript, 'printComplexLocal',
                () async {
              final event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              final result = await setup.service
                  .evaluateInFrame(isolateId, event.topFrame!.index!, 'record');
              expect(result, isA<InstanceRef>());

              final instanceRef = result as InstanceRef;
              expect(instanceRef.id, isNotNull);
              expect(instanceRef.kind, InstanceKind.kRecord);
              expect(instanceRef.length, 3);

              expect(await getFields(isolateId, instanceRef), {
                '0': 'true',
                '1': '3',
                '2': {'a': '1', 'b': '5'}
              });
              expect(await getFields(isolateId, instanceRef, offset: 0), {
                '0': 'true',
                '1': '3',
                '2': {'a': '1', 'b': '5'}
              });
              expect(await getFields(isolateId, instanceRef, offset: 1), {
                '1': '3',
                '2': {'a': '1', 'b': '5'}
              });
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 0),
                  {});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 1),
                  {'0': 'true'});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 2),
                  {'0': 'true', '1': '3'});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 5),
                  {
                    '0': 'true',
                    '1': '3',
                    '2': {'a': '1', 'b': '5'}
                  });
            });
          });

          test('can evaluate and display complex records fields', () async {
            await onBreakPoint(isolateId, mainScript, 'printComplexLocal',
                () async {
              final event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              final result = await setup.service.evaluateInFrame(
                  isolateId, event.topFrame!.index!, r'record.$2');
              expect(result, isA<InstanceRef>());

              final instanceRef = result as InstanceRef;
              expect(instanceRef.id, isNotNull);

              final instanceId = instanceRef.id!;
              final instance =
                  await setup.service.getObject(isolateId, instanceId);

              expect(
                  instance,
                  isA<Instance>()
                      .having((e) => e.kind, 'kind', InstanceKind.kMap)
                      .having((e) => e.classRef!.name, 'classRef.name',
                          'IdentityMap<String, int>'));
            });
          });

          test('can evaluate and display nested records', () async {
            await onBreakPoint(isolateId, mainScript, 'printNestedLocal',
                () async {
              final event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              final result = await setup.service
                  .evaluateInFrame(isolateId, event.topFrame!.index!, 'record');
              expect(result, isA<InstanceRef>());

              final instanceRef = result as InstanceRef;
              expect(instanceRef.id, isNotNull);
              expect(instanceRef.kind, InstanceKind.kRecord);
              expect(instanceRef.length, 2);

              expect(await getFields(isolateId, instanceRef), {
                '0': 'true',
                '1': {'0': 'false', '1': '5'}
              });
              expect(await getFields(isolateId, instanceRef, offset: 0), {
                '0': 'true',
                '1': {'0': 'false', '1': '5'}
              });
              expect(await getFields(isolateId, instanceRef, offset: 1), {
                '1': {'0': 'false', '1': '5'}
              });
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 0),
                  {});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 1),
                  {'0': 'true'});
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 2),
                  {
                    '0': 'true',
                    '1': {'0': 'false', '1': '5'}
                  });
              expect(
                  await getFields(isolateId, instanceRef, offset: 0, count: 5),
                  {
                    '0': 'true',
                    '1': {'0': 'false', '1': '5'}
                  });
            });
          });

          test('can evaluate and display nested records fields', () async {
            await onBreakPoint(isolateId, mainScript, 'printNestedLocal',
                () async {
              final event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              final result = await setup.service.evaluateInFrame(
                  isolateId, event.topFrame!.index!, r'record.$1');
              expect(result, isA<InstanceRef>());

              final instanceRef = result as InstanceRef;
              expect(instanceRef.id, isNotNull);
              expect(instanceRef.kind, InstanceKind.kRecord);
              expect(instanceRef.length, 2);

              final instanceId = instanceRef.id!;
              final instance =
                  await setup.service.getObject(isolateId, instanceId);

              expect(
                  instance,
                  isA<Instance>()
                      .having((e) => e.kind, 'kind', InstanceKind.kRecord)
                      .having((e) => e.classRef!.name, 'classRef.name',
                          'RecordType(bool, int)'));

              expect(await getFields(isolateId, instanceRef),
                  {'0': 'false', '1': '5'});
              expect(await getFields(isolateId, instanceRef, offset: 0),
                  {'0': 'false', '1': '5'});
            });
          });
        });
      });
    });
  }
}
