// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/fixtures/project.dart';
import 'package:dwds_test_common/fixtures/utilities.dart';
import 'package:dwds_test_common/logging.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

const originalString = 'Hello World!';
const newString = 'Bonjour le monde!';
const anotherString = 'Hola Mundo!';

void runTests({
  required TestSdkConfigurationProvider provider,
  required TestContextFactory contextFactory,
}) {
  final project = TestProject.testHotReload;
  final context = contextFactory(project, provider);

  Future<void> recompile({
    bool fullRestart = false,
    bool hasEdits = false,
    bool allowFailure = false,
  }) async {
    if (context.usesBuildDaemon) {
      if (hasEdits) {
        await context.waitForSuccessfulBuild(allowFailure: allowFailure);
      }
    } else {
      await context.recompile(
        fullRestart: fullRestart,
        allowFailure: allowFailure,
      );
    }
  }

  Future<void> makeEditAndRecompile() async {
    await context.makeEdits([
      (
        file: 'library1.dart',
        originalString: originalString,
        newString: newString,
      ),
    ]);
    await recompile(hasEdits: true);
  }

  // Call the method `evaluate` in the program and wait for `expectedString` to
  // be printed to the console.
  Future<void> callEvaluateAndWaitForLog(String expectedString) async {
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
    await completer.future.timeout(
      const Duration(minutes: 1),
      onTimeout: () {
        throw TimeoutException(
          "Failed to find log: '$expectedString' in console.",
        );
      },
    );
    await subscription.cancel();
  }

  group('Injected client', () {
    late VmService fakeClient;

    setUp(() async {
      setCurrentLogWriter(debug: provider.verbose);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          verboseCompiler: true,
          moduleFormat: provider.ddcModuleFormat,
          canaryFeatures: provider.canaryFeatures,
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
      var report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await context.makeEdits([
        (
          file: 'library1.dart',
          originalString: newString,
          newString: anotherString,
        ),
      ]);
      await recompile(hasEdits: true);
      report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await callEvaluateAndWaitForLog(anotherString);
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

      await callEvaluateAndWaitForLog(originalString);

      // Hot reload.
      await makeEditAndRecompile();
      report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await callEvaluateAndWaitForLog(newString);

      // Empty hot reload.
      await recompile();
      report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      await callEvaluateAndWaitForLog(newString);
    });

    test('can reject hot reload and recover with hot restart', () async {
      final client = context.debugConnection.vmService;

      await context.makeEdits([
        (
          file: 'library1.dart',
          originalString: "String get reloadValue => '$originalString';",
          newString:
              '''
String get reloadValue => '$newString';
class Bar {}
class Baz {}
class Foo extends Bar {}
''',
        ),
      ]);
      await recompile(hasEdits: true);
      final vm = await client.getVM();
      final isolate = await client.getIsolate(vm.isolates!.first.id!);
      var report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, true);

      // Make an illegal edit.
      await context.makeEdits([
        (
          file: 'library1.dart',
          originalString: 'class Foo extends Bar',
          newString: 'class Foo<T> extends Bar',
        ),
      ]);
      await recompile(hasEdits: true, allowFailure: true);
      report = await fakeClient.reloadSources(isolate.id!);
      expect(report.success, false);

      // Successfully recover with hot restart.
      await recompile(fullRestart: true, hasEdits: false);
      await callEvaluateAndWaitForLog(newString);
    });
  }, timeout: const Timeout.factor(2));
}
