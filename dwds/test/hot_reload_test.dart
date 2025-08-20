// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

const originalString = 'Hello World!';
const newString = 'Bonjour le monde!';

void main() {
  // Enable verbose logging for debugging.
  const debug = false;
  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    canaryFeatures: true,
    ddcModuleFormat: ModuleFormat.ddc,
  );
  final project = TestProject.testHotReload;
  final context = TestContext(project, provider);

  tearDownAll(provider.dispose);

  Future<void> recompile() async {
    await context.recompile(fullRestart: false);
  }

  Future<void> makeEditAndRecompile() async {
    await context.makeEdits([
      (
        file: 'library1.dart',
        originalString: originalString,
        newString: newString,
      ),
    ]);
    await recompile();
  }

  // Call `evaluate` through an expression evaluation and wait for
  // `expectedString` to be printed.
  Future<void> callEvaluateAndExpectLog(String expectedString) async {
    final client = context.debugConnection.vmService;
    final completer = Completer<void>();
    final subscription = context.webkitDebugger.onConsoleAPICalled.listen((e) {
      if (e.args.first.value == expectedString) {
        completer.complete();
      }
    });
    final vm = await client.getVM();
    final isolate = await client.getIsolate(vm.isolates!.first.id!);
    final rootLib = isolate.rootLib;
    await client.evaluate(isolate.id!, rootLib!.id!, 'evaluate()');
    await completer.future;
    await subscription.cancel();
  }

  group('Injected client', () {
    late VmService fakeClient;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          compilationMode: CompilationMode.frontendServer,
          moduleFormat: ModuleFormat.ddc,
          canaryFeatures: true,
        ),
      );
      fakeClient = await context.connectFakeClient();
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('can hot reload', () async {
      final client = context.debugConnection.vmService;

      await makeEditAndRecompile();
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      final report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await callEvaluateAndExpectLog(newString);
    });

    test('can hot reload with no changes, hot reload with changes, and '
        'hot reload again with no changes', () async {
      final client = context.debugConnection.vmService;

      // Empty hot reload.
      await recompile();
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      var report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await callEvaluateAndExpectLog(originalString);

      // Hot reload.
      await makeEditAndRecompile();
      report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await callEvaluateAndExpectLog(newString);

      // Empty hot reload.
      await recompile();
      report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await callEvaluateAndExpectLog(newString);
    });
  }, timeout: Timeout.factor(2));
}
