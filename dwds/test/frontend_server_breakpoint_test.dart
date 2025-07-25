// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
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

void main() {
  // Enable verbose logging for debugging.
  const debug = false;

  final provider = TestSdkConfigurationProvider(verbose: debug);
  tearDownAll(provider.dispose);

  final context = TestContext(TestProject.testPackage(), provider);

  // Change to 'true' to print expression compiler messages to console.
  //
  // Note: expression compiler runs in an isolate, so its output is not
  // currently redirected to a logger. As a result, it will be printed
  // regardless of the logger settings.
  final verboseCompiler = false;
  group('shared context', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: CompilationMode.frontendServer,
          verboseCompiler: verboseCompiler,
        ),
      );
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('breakpoint', () {
      late VmServiceInterface service;
      VM vm;
      late Isolate isolate;
      late String isolateId;
      ScriptList scripts;
      late ScriptRef mainScript;
      late String mainScriptUri;
      late Stream<Event> stream;

      setUp(() async {
        service = context.service;
        setCurrentLogWriter(debug: debug);
        vm = await service.getVM();
        isolate = await service.getIsolate(vm.isolates!.first.id!);
        isolateId = isolate.id!;
        scripts = await service.getScripts(isolateId);

        await service.streamListen('Debug');
        stream = service.onEvent('Debug');

        mainScript = scripts.scripts!.firstWhere(
          (each) => each.uri!.contains('main.dart'),
        );
        mainScriptUri = mainScript.uri!;
      });

      tearDown(() async {
        await service.resume(isolateId);
      });

      test('set breakpoint', () async {
        final line = await context.findBreakpointLine(
          'printLocal',
          isolateId,
          mainScript,
        );
        final bp = await service.addBreakpointWithScriptUri(
          isolateId,
          mainScriptUri,
          line,
        );

        await stream.firstWhere(
          (Event event) => event.kind == EventKind.kPauseBreakpoint,
        );

        expect(bp, isNotNull);

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolateId, bp.id!);
      });

      test('set breakpoint again', () async {
        final line = await context.findBreakpointLine(
          'printLocal',
          isolateId,
          mainScript,
        );
        final bp = await service.addBreakpointWithScriptUri(
          isolateId,
          mainScriptUri,
          line,
        );

        await stream.firstWhere(
          (Event event) => event.kind == EventKind.kPauseBreakpoint,
        );

        expect(bp, isNotNull);

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolateId, bp.id!);
      });

      test('set breakpoint inside a JavaScript line succeeds', () async {
        final line = await context.findBreakpointLine(
          'printNestedObjectMultiLine',
          isolateId,
          mainScript,
        );
        final column = 0;
        final bp = await service.addBreakpointWithScriptUri(
          isolateId,
          mainScriptUri,
          line,
          column: column,
        );

        await stream.firstWhere(
          (Event event) => event.kind == EventKind.kPauseBreakpoint,
        );

        expect(bp, isNotNull);
        expect(
          bp.location,
          isA<SourceLocation>()
              .having((loc) => loc.script, 'script', equals(mainScript))
              .having((loc) => loc.line, 'line', equals(line))
              .having((loc) => loc.column, 'column', greaterThan(column)),
        );

        // Remove breakpoint so it doesn't impact other tests.
        await service.removeBreakpoint(isolateId, bp.id!);
      });
    });
  });
}
