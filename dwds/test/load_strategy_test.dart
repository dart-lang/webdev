// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 1))

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'fixtures/context.dart';
import 'fixtures/fakes.dart';
import 'fixtures/project.dart';

void main() {
  final provider = TestSdkConfigurationProvider();
  tearDownAll(provider.dispose);

  final context = TestContext(TestProject.testWithSoundNullSafety, provider);

  setUpAll(() async {
    await context.setUp();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  group('Load Strategy', () {
    group(
        'When the packageConfigLocator does not specify a package config path',
        () {
      final strategy = FakeStrategy(FakeAssetReader());

      test('defaults to "./dart_tool/package_config.json"', () {
        expect(
          p.split(strategy.packageConfigPath).join('/'),
          endsWith('_testSound/.dart_tool/package_config.json'),
        );
      });
    });

    group('When a custom package config path is specified', () {
      final strategy = FakeStrategy(
        FakeAssetReader(),
        packageConfigPath: 'custom/package_config/path',
      );

      test('uses the specified package config path', () {
        expect(
          strategy.packageConfigPath,
          equals('custom/package_config/path'),
        );
      });
    });
  });
}
