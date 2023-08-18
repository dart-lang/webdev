// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 1))

import 'package:dwds/asset_reader.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'fixtures/context.dart';
import 'fixtures/fakes.dart';
import 'fixtures/project.dart';

class LoadStrategyCustomPackageConfig extends FakeStrategy {
  LoadStrategyCustomPackageConfig(
    AssetReader assetReader,
  ) : super(assetReader);

  @override
  String? packageConfigLocator(String entrypoint) =>
      '$entrypoint/custom/package_config/path';
}

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

      test('defaults to "./dart_tool/packageconfig.json"', () {
        strategy.trackEntrypoint('my_app/entrypoint');
        expect(
          strategy.packageConfigPath,
          endsWith('_testSound/.dart_tool/package_config.json'),
        );
      });
    });

    group('When the packageConfigLocator specifies a package config path', () {
      final strategy = LoadStrategyCustomPackageConfig(FakeAssetReader());

      test('uses the specified package config path', () {
        strategy.trackEntrypoint('my_app/entrypoint');
        expect(
          strategy.packageConfigPath,
          equals('my_app/entrypoint/custom/package_config/path'),
        );
      });
    });
  });
}
