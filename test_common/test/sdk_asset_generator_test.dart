// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

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
    late String soundSdkJsPath;
    late String soundSdkJsMapPath;

    // Missing weak assets
    late String weakSdkSummaryPath;
    late String weakSdkFullDillPath;
    late String weakSdkJsPath;
    late String weakSdkJsMapPath;

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
      soundSdkJsPath = copySdkLayout.soundJsPath;
      soundSdkJsMapPath = copySdkLayout.soundJsMapPath;

      _deleteIfExists(soundSdkFullDillPath);
      _deleteIfExists(soundSdkJsPath);
      _deleteIfExists(soundSdkJsMapPath);

      // Simulate missing weak assets.
      weakSdkSummaryPath = copySdkLayout.weakSummaryPath;
      weakSdkFullDillPath = copySdkLayout.weakFullDillPath;
      weakSdkJsPath = copySdkLayout.weakJsPath;
      weakSdkJsMapPath = copySdkLayout.weakJsMapPath;

      _deleteIfExists(weakSdkSummaryPath);
      _deleteIfExists(weakSdkFullDillPath);
      _deleteIfExists(weakSdkJsPath);
      _deleteIfExists(weakSdkJsMapPath);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Can generate missing SDK assets and validate SDK configuration',
        () async {
      final sdkLayout = TestSdkLayout.createDefault(sdkDirectory);
      final configuration = TestSdkLayout.createConfiguration(sdkLayout);

      final assetGenerator = SdkAssetGenerator(
        sdkLayout: sdkLayout,
        verbose: true,
        canaryFeatures: false,
      );
      await assetGenerator.generateSdkAssets();

      // Make sure SDK configuration and asset generator agree on the file paths.
      expect(configuration.sdkDirectory, equals(sdkDirectory));
      expect(configuration.compilerWorkerPath, equals(compilerWorkerPath));

      expect(sdkLayout.soundSummaryPath, equals(soundSdkSummaryPath));
      expect(sdkLayout.soundFullDillPath, equals(soundSdkFullDillPath));
      expect(sdkLayout.soundJsPath, equals(soundSdkJsPath));
      expect(sdkLayout.soundJsMapPath, equals(soundSdkJsMapPath));

      expect(sdkLayout.weakSummaryPath, equals(weakSdkSummaryPath));
      expect(sdkLayout.weakFullDillPath, equals(weakSdkFullDillPath));
      expect(sdkLayout.weakJsPath, equals(weakSdkJsPath));
      expect(sdkLayout.weakJsMapPath, equals(weakSdkJsMapPath));

      // Validate that configuration files exist.
      configuration.validateSdkDir();
      configuration.validate();

      // Validate all assets exist.
      expect(sdkLayout.soundSummaryPath, _exists);
      expect(sdkLayout.soundFullDillPath, _exists);
      expect(sdkLayout.soundJsPath, _exists);
      expect(sdkLayout.soundJsMapPath, _exists);

      expect(sdkLayout.weakSummaryPath, _exists);
      expect(sdkLayout.weakFullDillPath, _exists);
      expect(sdkLayout.weakJsPath, _exists);
      expect(sdkLayout.weakJsMapPath, _exists);
    });

    test('Can generate missing SDK assets with canary features enabled',
        () async {
      final sdkLayout = TestSdkLayout.createDefault(sdkDirectory);

      final assetGenerator = SdkAssetGenerator(
        sdkLayout: sdkLayout,
        verbose: true,
        canaryFeatures: true,
      );
      await assetGenerator.generateSdkAssets();

      final soundSdk = File(soundSdkJsPath).readAsStringSync();
      expect(soundSdk, contains('canary'));

      final weakSdk = File(weakSdkJsPath).readAsStringSync();
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
