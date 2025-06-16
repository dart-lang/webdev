// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

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

  Future<void> makeEditAndRecompile() async {
    context.makeEditToDartLibFile(
      libFileName: 'library1.dart',
      toReplace: originalString,
      replaceWith: newString,
    );
    await context.recompile(fullRestart: false);
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

      var source = await context.webDriver.pageSource;
      // Should not contain the change until the function that updates the page
      // is evaluated in a hot reload.
      expect(source, contains(originalString));
      expect(source.contains(newString), false);

      final rootLib = isolate.rootLib;
      await client.evaluate(isolate.id!, rootLib!.id!, 'evaluate()');
      source = await context.webDriver.pageSource;
      expect(source, contains(newString));
      expect(source.contains(originalString), false);
    });
  }, timeout: Timeout.factor(2));
}
