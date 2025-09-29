// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service_interface/vm_service_interface.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

void testAll({
  required TestSdkConfigurationProvider provider,
  CompilationMode compilationMode = CompilationMode.buildDaemon,
  IndexBaseMode indexBaseMode = IndexBaseMode.noBase,
  bool useDebuggerModuleNames = false,
  bool debug = false,
}) {
  if (compilationMode == CompilationMode.buildDaemon &&
      indexBaseMode == IndexBaseMode.base) {
    throw StateError(
      'build daemon scenario does not support non-empty base in index file',
    );
  }

  final testParts = TestProject.testParts(baseMode: indexBaseMode);

  final context = TestContext(testParts, provider);

  Future<void> onBreakPoint(
    String isolate,
    ScriptRef script,
    String breakPointId,
    Future<void> Function() body,
  ) async {
    Breakpoint? bp;
    try {
      final line = await context.findBreakpointLine(
        breakPointId,
        isolate,
        script,
      );
      bp = await context.service.addBreakpointWithScriptUri(
        isolate,
        script.uri!,
        line,
      );
      await body();
    } finally {
      // Remove breakpoint so it doesn't impact other tests or retries.
      if (bp != null) {
        await context.service.removeBreakpoint(isolate, bp.id!);
      }
    }
  }

  group('shared context with evaluation - evaluateInFrame', () {
    late VmServiceInterface service;
    late String isolateId;
    late ScriptRef mainScript;
    late ScriptRef part1Script;
    late ScriptRef part2Script;
    late ScriptRef part3Script;
    late Stream<Event> stream;

    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          enableExpressionEvaluation: true,
          useDebuggerModuleNames: useDebuggerModuleNames,
          verboseCompiler: debug,
        ),
      );

      service = context.service;
      final vm = await service.getVM();
      final isolate = await service.getIsolate(vm.isolates!.first.id!);
      isolateId = isolate.id!;
      final scripts = await service.getScripts(isolateId);

      ScriptRef findScript(String path) {
        return scripts.scripts!.firstWhere((e) => e.uri!.contains(path));
      }

      await service.streamListen('Debug');
      stream = service.onEvent('Debug');

      final packageName = testParts.packageName;

      mainScript = findScript('package:$packageName/library.dart');
      part1Script = findScript('package:$packageName/part1.dart');
      part2Script = findScript('package:$packageName/part2.dart');
      part3Script = findScript('package:$packageName/part3.dart');
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    tearDown(() async {
      await service.resume(isolateId);
    });

    test('evaluate expression in main library', () async {
      await onBreakPoint(isolateId, mainScript, 'Concatenate1', () async {
        final event = await stream.firstWhere(
          (event) => event.kind == EventKind.kPauseBreakpoint,
        );

        final result = await context.service.evaluateInFrame(
          isolateId,
          event.topFrame!.index!,
          'a.substring(2, 4)',
        );

        expect(
          result,
          isA<InstanceRef>().having(
            (instance) => instance.valueAsString,
            'valueAsString',
            'll',
          ),
        );
      });
    });

    test('evaluate expression in part1', () async {
      await onBreakPoint(isolateId, part1Script, 'Concatenate2', () async {
        final event = await stream.firstWhere(
          (event) => event.kind == EventKind.kPauseBreakpoint,
        );

        final result = await context.service.evaluateInFrame(
          isolateId,
          event.topFrame!.index!,
          'a + b + 37',
        );

        expect(
          result,
          isA<InstanceRef>().having(
            (instance) => instance.valueAsString,
            'valueAsString',
            '42',
          ),
        );
      });
    });

    test('evaluate expression in part2', () async {
      await onBreakPoint(isolateId, part2Script, 'Concatenate3', () async {
        final event = await stream.firstWhere(
          (event) => event.kind == EventKind.kPauseBreakpoint,
        );

        final result = await context.service.evaluateInFrame(
          isolateId,
          event.topFrame!.index!,
          'a.length + b + 1',
        );

        expect(
          result,
          isA<InstanceRef>().having(
            (instance) => instance.valueAsString,
            'valueAsString',
            '42.42',
          ),
        );
      });
    });

    test('evaluate expression in part3', () async {
      await onBreakPoint(isolateId, part3Script, 'Concatenate4', () async {
        final event = await stream.firstWhere(
          (event) => event.kind == EventKind.kPauseBreakpoint,
        );

        final result = await context.service.evaluateInFrame(
          isolateId,
          event.topFrame!.index!,
          '(List.of(a)..add(b.keys.first)).toString()',
        );

        expect(
          result,
          isA<InstanceRef>().having(
            (instance) => instance.valueAsString,
            'valueAsString',
            '[hello, world, foo]',
          ),
        );
      });
    });
  });
}
