// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:dwds/src/utilities/sdk_asset_generator.dart';
import 'package:dwds/src/utilities/sdk_configuration.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/logging.dart';

void main() {
  group('SDK asset generator', () {
    final bool debug = false;

    late final Directory tempDir;
    late String sdkDirectory;
    late final String soundSdkSummaryPath;
    late final String librariesPath;
    late final String compilerWorkerPath;

    // Missing sound assets
    late final String soundSdkFullDillPath;
    late final String soundSdkJsPath;
    late final String soundSdkJsMapPath;

    // Missing weak assets
    late final String unsoundSdkSummaryPath;
    late final String unsoundSdkFullDillPath;
    late final String unsoundSdkJsPath;
    late final String unsoundSdkJsMapPath;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      tempDir = Directory.systemTemp.createTempSync();

      sdkDirectory = tempDir.path;
      soundSdkSummaryPath = _dartSoundSdkSummaryPath(sdkDirectory);
      librariesPath = _librariesPath(sdkDirectory);
      compilerWorkerPath = _compilerWorkerPath(sdkDirectory);

      // Copy the SDK directory into a temp directory.
      await _copy(SdkLayout.sdkDir, sdkDirectory);

      // Simulate missing sound assets.
      soundSdkFullDillPath = _dartSoundSdkFullDillPath(sdkDirectory);
      soundSdkJsPath = _dartSoundSdkJsPath(sdkDirectory);
      soundSdkJsMapPath = _dartSoundSdkJsMapPath(sdkDirectory);

      _deleteIfExists(soundSdkFullDillPath);
      _deleteIfExists(soundSdkJsPath);
      _deleteIfExists(soundSdkJsMapPath);

      // Simulate missing weak assets.
      unsoundSdkSummaryPath = _dartUnsoundSdkSummaryPath(sdkDirectory);
      unsoundSdkFullDillPath = _dartUnsoundSdkFullDillPath(sdkDirectory);
      unsoundSdkJsPath = _dartUnsoundSdkJsPath(sdkDirectory);
      unsoundSdkJsMapPath = _dartUnsoundSdkJsMapPath(sdkDirectory);

      _deleteIfExists(unsoundSdkSummaryPath);
      _deleteIfExists(unsoundSdkFullDillPath);
      _deleteIfExists(unsoundSdkJsPath);
      _deleteIfExists(unsoundSdkJsMapPath);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('Can generate missing SDK assets and validate SDK configuration',
        () async {
      final sdkLayout = SdkLayout.createDefault(sdkDirectory);
      final configuration = SdkConfiguration.fromSdkLayout(sdkLayout);

      final assetGenerator =
          SdkAssetGenerator(sdkLayout: sdkLayout, verboseCompiler: true);
      await assetGenerator.generateSdkAssets();

      // Make sure SDK configuration and asset generator agree on the file paths.
      expect(configuration.sdkDirectory, equals(sdkDirectory));
      expect(configuration.librariesPath, equals(librariesPath));
      expect(configuration.compilerWorkerPath, equals(compilerWorkerPath));

      expect(sdkLayout.soundSummaryPath, equals(soundSdkSummaryPath));
      expect(sdkLayout.soundFullDillPath, equals(soundSdkFullDillPath));
      expect(sdkLayout.soundJsPath, equals(soundSdkJsPath));
      expect(sdkLayout.soundJsMapPath, equals(soundSdkJsMapPath));

      expect(sdkLayout.weakSummaryPath, equals(unsoundSdkSummaryPath));
      expect(sdkLayout.weakFullDillPath, equals(unsoundSdkFullDillPath));
      expect(sdkLayout.weakJsPath, equals(unsoundSdkJsPath));
      expect(sdkLayout.weakJsMapPath, equals(unsoundSdkJsMapPath));

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

String _dartUnsoundSdkSummaryPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_sdk.dill');

String _dartSoundSdkSummaryPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_outline_sound.dill');

String _dartUnsoundSdkFullDillPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_platform.dill');

String _dartSoundSdkFullDillPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_platform_sound.dill');

String _dartUnsoundSdkJsPath(String sdkDir) =>
    p.join(sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk.js');

String _dartSoundSdkJsPath(String sdkDir) =>
    p.join(sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk_sound.js');

String _dartUnsoundSdkJsMapPath(String sdkDir) =>
    p.join(sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk.js.map');

String _dartSoundSdkJsMapPath(String sdkDir) => p.join(
    sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk_sound.js.map');

String _librariesPath(String sdkDir) => p.join(sdkDir, 'lib', 'libraries.json');

String _compilerWorkerPath(String sdkDir) =>
    p.join(sdkDir, 'bin', 'snapshots', 'dartdevc.dart.snapshot');

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
