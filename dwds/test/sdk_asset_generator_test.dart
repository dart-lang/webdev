// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:dwds/sdk_configuration.dart';
import 'package:test/test.dart';

import 'fixtures/logging.dart';
import 'fixtures/utilities.dart';
import 'fixtures/sdk_asset_generator.dart';

void main() {
  group('SDK asset generator', () {
    final bool debug = false;

    late Directory tempDir;
    late String sdkDirectory;

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
      final sdkLayout = SdkLayout.createDefault(sdkDirectory);

      soundSdkJsPath = sdkLayout.soundJsPath;
      soundSdkJsMapPath = sdkLayout.soundJsMapPath;
      soundSdkFullDillPath = sdkLayout.soundFullDillPath;

      weakSdkJsPath = sdkLayout.weakJsPath;
      weakSdkJsMapPath = sdkLayout.weakJsMapPath;
      weakSdkSummaryPath = sdkLayout.weakSummaryPath;
      weakSdkFullDillPath = sdkLayout.weakFullDillPath;

      // Copy the SDK directory into a temp directory.
      await copyDirectory(SdkLayout.defaultSdkDirectory, sdkDirectory);

      // Simulate missing sound assets.
      _deleteIfExists(soundSdkFullDillPath);
      _deleteIfExists(soundSdkJsPath);
      _deleteIfExists(soundSdkJsMapPath);

      // Simulate missing weak assets.

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
      final sdkLayout = SdkLayout.createDefault(sdkDirectory);
      final configuration = SdkConfiguration(sdkLayout);

      final assetGenerator =
          SdkAssetGenerator(sdkLayout: sdkLayout, verboseCompiler: true);
      await assetGenerator.generateSdkAssets();

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
  });
}

Matcher _exists = predicate((String path) => File(path).existsSync());

void _deleteIfExists(String path) {
  final file = File(path);
  if (file.existsSync()) {
    file.deleteSync();
  }
}
