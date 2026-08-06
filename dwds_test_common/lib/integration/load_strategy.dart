// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/dwds.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../fixtures/context.dart';
import '../fixtures/fakes.dart';
import '../fixtures/project.dart';
import '../fixtures/utilities.dart';
import '../test_sdk_configuration.dart';

void runIndependentTests() {
  group('Fake Strategy', () {
    group(
      'When the packageConfigLocator does not specify a package config path',
      () {
        late final strategy = FakeStrategy(FakeAssetReader());

        test('defaults to "./dart_tool/package_config.json"', () {
          expect(
            p.split(strategy.packageConfigPath).join('/'),
            endsWith('.dart_tool/package_config.json'),
          );
        });
      },
    );

    group('When a custom package config path is specified', () {
      late final strategy = FakeStrategy(
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

    group('When default build settings defined', () {
      late final strategy = FakeStrategy(
        FakeAssetReader(),
        buildSettings: const TestBuildSettings.dart(),
      );

      test('uses the default app entrypoint', () {
        expect(strategy.buildSettings.appEntrypoint, isNull);
      });

      test('uses the default canary features setting', () {
        expect(strategy.buildSettings.canaryFeatures, isFalse);
      });

      test('uses the default flutter app setting', () {
        expect(strategy.buildSettings.isFlutterApp, isFalse);
      });

      test('uses the default experiments', () {
        expect(strategy.buildSettings.experiments, isEmpty);
      });
    });

    group('When custom build settings defined', () {
      final appEntrypoint = Uri.parse('main.dart');
      final canaryFeatures = true;
      final isFlutterApp = true;
      final experiments = ['records'];

      late final strategy = FakeStrategy(
        FakeAssetReader(),
        buildSettings: BuildSettings(
          appEntrypoint: appEntrypoint,
          isFlutterApp: isFlutterApp,
          canaryFeatures: canaryFeatures,
          experiments: experiments,
        ),
      );

      test('uses the specified app entrypoint', () {
        expect(strategy.buildSettings.appEntrypoint, appEntrypoint);
      });

      test('uses the specified canary features setting', () {
        expect(strategy.buildSettings.canaryFeatures, canaryFeatures);
      });

      test('uses the specified flutter app setting', () {
        expect(strategy.buildSettings.isFlutterApp, isFlutterApp);
      });

      test('uses the specified experiments', () {
        expect(strategy.buildSettings.experiments, experiments);
      });
    });
  });
}

void runDependentTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
}) {
  final project = TestProject.test;
  final context = TestContext(project, provider);

  group('Global load Strategy with default build settings', () {
    setUpAll(() async {
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          moduleFormat: provider.ddcModuleFormat,
          canaryFeatures: provider.canaryFeatures,
        ),
      );
    });

    tearDownAll(context.tearDown);

    test('provides build settings', () {
      final loadStrategy = globalToolConfiguration.loadStrategy;
      expect(
        loadStrategy.buildSettings.appEntrypoint,
        project.dartEntryFilePackageUri,
      );
      expect(
        loadStrategy.buildSettings.canaryFeatures,
        provider.canaryFeatures,
      );
      expect(loadStrategy.buildSettings.isFlutterApp, isFalse);
      expect(loadStrategy.buildSettings.experiments, isEmpty);
    });
  });

  group('Global load Strategy with custom build settings ', () {
    final canaryFeatures = provider.canaryFeatures;
    final isFlutterApp = true;
    final experiments = ['records'];

    setUpAll(() async {
      await context.setUp(
        testSettings: TestSettings(
          compilationMode: compilationMode,
          canaryFeatures: canaryFeatures,
          isFlutterApp: isFlutterApp,
          experiments: experiments,
          moduleFormat: provider.ddcModuleFormat,
        ),
      );
    });

    tearDownAll(context.tearDown);

    test('provides custom build settings', () {
      final loadStrategy = globalToolConfiguration.loadStrategy;
      expect(
        loadStrategy.buildSettings.appEntrypoint,
        project.dartEntryFilePackageUri,
      );
      expect(loadStrategy.buildSettings.canaryFeatures, canaryFeatures);
      expect(loadStrategy.buildSettings.isFlutterApp, isFlutterApp);
      expect(loadStrategy.buildSettings.experiments, experiments);
    });
  });
}
