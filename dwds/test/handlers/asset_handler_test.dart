// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';

import '../fixtures/context.dart';
import '../fixtures/project.dart';
import '../fixtures/utilities.dart';

void main() {
  group('Asset handler', () {
    final provider = TestSdkConfigurationProvider();
    final context = TestContext(TestProject.testWithSoundNullSafety, provider);

    setUpAll(() async {
      setCurrentLogWriter();
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          verboseCompiler: false,
        ),
      );
    });

    tearDownAll(() async {
      await context.tearDown();
      provider.dispose();
    });

    setUp(setCurrentLogWriter);

    Future<void> readAsString(String path) async {
      final request = Request('GET', Uri.parse('http://foo:0000/$path'));
      final response = await context.assetHandler(request);
      expect(response.statusCode, 200);
      final result = await response.readAsString();
      expect(
        result,
        isNotNull,
        reason: 'Failed to read $path: ${response.statusCode}',
      );
    }

    Future<void> readAsBytes(String path) async {
      final request = Request('GET', Uri.parse('http://foo:0000/$path'));
      final response = await context.assetHandler(request);
      expect(response.statusCode, 200);
      final result = await response.read().toList();
      expect(
        result,
        isNotNull,
        reason: 'Failed to read $path: ${response.statusCode}',
      );
    }

    test('can read dill files', () async {
      final path = 'hello_world/main.ddc.full.dill';
      await readAsBytes(path);
    });

    test('can read large number of resources simultaneously', () async {
      final n = 1000;
      final futures = [
        for (var i = 0; i < n; i++) readAsString('hello_world/main.ddc.js.map'),
        for (var i = 0; i < n; i++) readAsString('hello_world/main.ddc.js'),
        for (var i = 0; i < n; i++)
          readAsBytes('hello_world/main.ddc.full.dill'),
      ];

      await expectLater(Future.wait(futures), completes);
    });
  });
}
