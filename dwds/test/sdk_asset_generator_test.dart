// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/logging.dart';
import 'fixtures/sdk_asset_generator.dart';
import 'fixtures/test_sdk_layout.dart';

void main() {
  group('SDK asset generator', () {
    final bool debug = false;

    late final Directory tempDir;
    late String sdkDirectory;
    late final String soundSdkSummaryPath;
    late final String compilerWorkerPath;

    // Missing sound assets
    late final String soundSdkFullDillPath;
    late final String soundSdkJsPath;
    late final String soundSdkJsMapPath;

    // Missing weak assets
    late final String weakSdkSummaryPath;
    late final String weakSdkFullDillPath;
    late final String weakSdkJsPath;
    late final String weakSdkJsMapPath;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      tempDir = Directory.systemTemp.createTempSync();

      sdkDirectory = tempDir.path;
      final copySdkLayout = TestSdkLayout.createDefault(sdkDirectory);

      soundSdkSummaryPath = copySdkLayout.soundSummaryPath;
      compilerWorkerPath = copySdkLayout.dartdevcSnapshotPath;

      // Copy the SDK directory into a temp directory.
      await _copy(TestSdkLayout.defaultSdkDirectory, sdkDirectory);

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

      final assetGenerator =
          SdkAssetGenerator(sdkLayout: sdkLayout, verboseCompiler: true);
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
  });
}

Matcher _exists = predicate((String path) => File(path).existsSync());

void _deleteIfExists(String path) {
  final file = File(path);
  if (file.existsSync()) {
    file.deleteSync();
  }
}

// Update modified files.
Future<void> _copy(String from, String to) async {
  if (!Directory(from).existsSync()) return;
  await Directory(to).create(recursive: true);

  await for (final file in Directory(from).list()) {
    final copyTo = p.join(to, p.relative(file.path, from: from));
    if (file is Directory) {
      await _copy(file.path, copyTo);
    } else if (file is File) {
      await File(file.path).copy(copyTo);
    } else if (file is Link) {
      await Link(copyTo).create(await file.target(), recursive: true);
    }
  }
}
