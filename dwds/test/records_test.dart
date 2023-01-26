// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'package:collection/collection.dart';
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
  final debug = true;

  final setup = TestSetup.sound();
  final context = setup.context;

  Future<void> onBreakPoint(String isolate, ScriptRef script,
      String breakPointId, Future<void> Function() body) async {
    Breakpoint? bp;
    try {
      final line =
          await context.findBreakpointLine(breakPointId, isolate, script);
      bp = await setup.service
          .addBreakpointWithScriptUri(isolate, script.uri!, line);
      await body();
    } finally {
      // Remove breakpoint so it doesn't impact other tests or retries.
      if (bp != null) {
        await setup.service.removeBreakpoint(isolate, bp.id!);
      }
    }
  }

  for (var compilationMode in [CompilationMode.frontendServer]) {
    group('$compilationMode |', () {
      setUpAll(() async {
        setCurrentLogWriter(debug: debug);
      });

      group('shared context with evaluation |', () {
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

          test('can evaluate and display records', () async {
            await onBreakPoint(isolateId, mainScript, 'printLocal', () async {
              final event = await stream.firstWhere(
                  (event) => event.kind == EventKind.kPauseBreakpoint);

              final result = await setup.service
                  .evaluateInFrame(isolateId, event.topFrame!.index!, 'record');

              //  Actual: InstanceRef:<[InstanceRef id: 5614429716467540672.1.54, kind: PlainInstance, identityHashCode: 912649884, classRef: [ClassRef id: classes|null|RecordType(bool, int), name: RecordType(bool, int), library: null]]>
              expect(result, isA<InstanceRef>());

              final instanceRef = result as InstanceRef;
              final instance = await setup.service
                  .getObject(isolateId, instanceRef.id!) as Instance;

              expect(instance.kind, InstanceKind.kRecord);

              final classRef = instance.classRef!;
              expect(classRef, isNotNull);
              expect(classRef.name, 'RecordType(bool, int)');

              final fieldNames = instance.fields!
                  .map((boundField) => boundField.name)
                  .whereNotNull()
                  .toList();
              expect(fieldNames, [
                r'$0',
                r'$1',
              ]);
            });
          });
        });
      });
    });
  }
}
