// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

void testAll({
  required TestSdkConfigurationProvider provider,
  bool debug = false,
}) {
  final context = TestContext(TestProject.test, provider);

  setUpAll(() async {
    setCurrentLogWriter(debug: debug);
    await context.setUp(
      testSettings: TestSettings(
        verboseCompiler: debug,
        moduleFormat: provider.ddcModuleFormat,
      ),
    );
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  test('can take screenshots', () async {
    final response = await context.debugConnection.vmService
        .callServiceExtension('ext.dwds.screenshot');
    expect(response.json!['data'], isNotNull);
  });
}
