// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/sdk_asset_generator.dart';
import 'package:test_common/test_sdk_layout.dart';

void main() {
  group('SDK asset generator', () {
    final bool debug = false;

    late Directory tempDir;
    late String sdkDirectory;
    late String soundSdkSummaryPath;
    late String compilerWorkerPath;

    // Missing sound assets
    late String soundSdkFullDillPath;
    late String soundAmdSdkJsPath;
    late String soundAmdSdkJsMapPath;
    late String soundDdcSdkJsPath;
    late String soundDdcSdkJsMapPath;

    // Missing weak assets
    late String weakSdkSummaryPath;
    late String weakSdkFullDillPath;
    late String weakAmdSdkJsPath;
    late String weakAmdSdkJsMapPath;
    late String weakDdcSdkJsPath;
    late String weakDdcSdkJsMapPath;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      tempDir = Directory.systemTemp.createTempSync();

      sdkDirectory = tempDir.path;
      final copySdkLayout = TestSdkLayout.createDefault(sdkDirectory);

      soundSdkSummaryPath = copySdkLayout.soundSummaryPath;
      compilerWorkerPath = copySdkLayout.dartdevcSnapshotPath;

      // Copy the SDK directory into a temp directory.
      await copyDirectory(TestSdkLayout.defaultSdkDirectory, sdkDirectory);

      // Simulate missing sound assets.
      soundSdkFullDillPath = copySdkLayout.soundFullDillPath;
      soundAmdSdkJsPath = copySdkLayout.soundAmdJsPath;
      soundAmdSdkJsMapPath = copySdkLayout.soundAmdJsMapPath;
      soundDdcSdkJsPath = copySdkLayout.soundDdcJsPath;
      soundDdcSdkJsMapPath = copySdkLayout.soundDdcJsMapPath;

      _deleteIfExists(soundSdkFullDillPath);
      _deleteIfExists(soundAmdSdkJsPath);
      _deleteIfExists(soundAmdSdkJsMapPath);
      _deleteIfExists(soundDdcSdkJsPath);
      _deleteIfExists(soundDdcSdkJsMapPath);

      // Simulate missing weak assets.
      weakSdkSummaryPath = copySdkLayout.weakSummaryPath;
      weakSdkFullDillPath = copySdkLayout.weakFullDillPath;
      weakAmdSdkJsPath = copySdkLayout.weakAmdJsPath;
      weakAmdSdkJsMapPath = copySdkLayout.weakAmdJsMapPath;
      weakDdcSdkJsPath = copySdkLayout.weakAmdJsPath;
      weakDdcSdkJsMapPath = copySdkLayout.weakAmdJsMapPath;

      _deleteIfExists(weakSdkSummaryPath);
      _deleteIfExists(weakSdkFullDillPath);
      _deleteIfExists(weakAmdSdkJsPath);
      _deleteIfExists(weakAmdSdkJsMapPath);
      _deleteIfExists(weakDdcSdkJsPath);
      _deleteIfExists(weakDdcSdkJsMapPath);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test(
        'Can generate missing SDK assets and validate SDK configuration for the AMD module system',
        () async {
      final sdkLayout = TestSdkLayout.createDefault(sdkDirectory);
      final configuration = TestSdkLayout.createConfiguration(sdkLayout);

      final assetGenerator = SdkAssetGenerator(
        sdkLayout: sdkLayout,
        verbose: true,
        canaryFeatures: false,
        ddcModuleFormat: ModuleFormat.amd,
      );
      await assetGenerator.generateSdkAssets();

      // Make sure SDK configuration and asset generator agree on the file paths.
      expect(configuration.sdkDirectory, equals(sdkDirectory));
      expect(configuration.compilerWorkerPath, equals(compilerWorkerPath));

      expect(sdkLayout.soundSummaryPath, equals(soundSdkSummaryPath));
      expect(sdkLayout.soundFullDillPath, equals(soundSdkFullDillPath));
      expect(sdkLayout.soundAmdJsPath, equals(soundAmdSdkJsPath));
      expect(sdkLayout.soundAmdJsMapPath, equals(soundAmdSdkJsMapPath));

      expect(sdkLayout.weakSummaryPath, equals(weakSdkSummaryPath));
      expect(sdkLayout.weakFullDillPath, equals(weakSdkFullDillPath));
      expect(sdkLayout.weakAmdJsPath, equals(weakAmdSdkJsPath));
      expect(sdkLayout.weakAmdJsMapPath, equals(weakAmdSdkJsMapPath));

      // Validate that configuration files exist.
      configuration.validateSdkDir();
      configuration.validate();

      // Validate all assets exist.
      expect(sdkLayout.soundSummaryPath, _exists);
      expect(sdkLayout.soundFullDillPath, _exists);
      expect(sdkLayout.soundAmdJsPath, _exists);
      expect(sdkLayout.soundAmdJsMapPath, _exists);

      expect(sdkLayout.weakSummaryPath, _exists);
      expect(sdkLayout.weakFullDillPath, _exists);
      expect(sdkLayout.weakAmdJsPath, _exists);
      expect(sdkLayout.weakAmdJsMapPath, _exists);
    });

    test(
        'Can generate missing SDK assets and validate SDK configuration for the DDC module system',
        () async {
      final sdkLayout = TestSdkLayout.createDefault(sdkDirectory);
      final configuration = TestSdkLayout.createConfiguration(sdkLayout);

      final assetGenerator = SdkAssetGenerator(
        sdkLayout: sdkLayout,
        verbose: true,
        canaryFeatures: false,
        ddcModuleFormat: ModuleFormat.ddc,
      );
      await assetGenerator.generateSdkAssets();

      // Make sure SDK configuration and asset generator agree on the file paths.
      expect(configuration.sdkDirectory, equals(sdkDirectory));
      expect(configuration.compilerWorkerPath, equals(compilerWorkerPath));

      expect(sdkLayout.soundSummaryPath, equals(soundSdkSummaryPath));
      expect(sdkLayout.soundFullDillPath, equals(soundSdkFullDillPath));
      expect(sdkLayout.soundDdcJsPath, equals(soundDdcSdkJsPath));
      expect(sdkLayout.soundDdcJsMapPath, equals(soundDdcSdkJsMapPath));

      expect(sdkLayout.weakSummaryPath, equals(weakSdkSummaryPath));
      expect(sdkLayout.weakFullDillPath, equals(weakSdkFullDillPath));
      expect(sdkLayout.weakDdcJsPath, equals(weakDdcSdkJsPath));
      expect(sdkLayout.weakDdcJsMapPath, equals(weakDdcSdkJsMapPath));

      // Validate that configuration files exist.
      configuration.validateSdkDir();
      configuration.validate();

      // Validate all assets exist.
      expect(sdkLayout.soundSummaryPath, _exists);
      expect(sdkLayout.soundFullDillPath, _exists);
      expect(sdkLayout.soundDdcJsPath, _exists);
      expect(sdkLayout.soundDdcJsMapPath, _exists);

      expect(sdkLayout.weakSummaryPath, _exists);
      expect(sdkLayout.weakFullDillPath, _exists);
      expect(sdkLayout.weakDdcJsPath, _exists);
      expect(sdkLayout.weakDdcJsMapPath, _exists);
    });

    test('Can generate missing SDK assets with canary features enabled',
        () async {
      final sdkLayout = TestSdkLayout.createDefault(sdkDirectory);

      final assetGenerator = SdkAssetGenerator(
        sdkLayout: sdkLayout,
        verbose: true,
        canaryFeatures: true,
        ddcModuleFormat: ModuleFormat.amd,
      );
      await assetGenerator.generateSdkAssets();

      final soundSdk = File(soundAmdSdkJsPath).readAsStringSync();
      expect(soundSdk, contains('canary'));

      final weakSdk = File(weakAmdSdkJsPath).readAsStringSync();
      expect(weakSdk, contains('canary'));
    });

    test(
        'Can generate missing SDK assets with canary features enabled for the DDC module system',
        () async {
      final sdkLayout = TestSdkLayout.createDefault(sdkDirectory);

      final assetGenerator = SdkAssetGenerator(
        sdkLayout: sdkLayout,
        verbose: true,
        canaryFeatures: true,
        ddcModuleFormat: ModuleFormat.ddc,
      );
      await assetGenerator.generateSdkAssets();

      final soundSdk = File(soundDdcSdkJsPath).readAsStringSync();
      expect(soundSdk, contains('canary'));

      final weakSdk = File(weakDdcSdkJsPath).readAsStringSync();
      expect(weakSdk, contains('canary'));
    });
  });
}

Matcher _exists =
    predicate((String path) => File(path).existsSync(), 'File exists');

void _deleteIfExists(String path) {
  final file = File(path);
  if (file.existsSync()) {
    file.deleteSync();
  }
}
