// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:dwds/src/utilities/sdk_configuration.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/logging.dart';
import 'fixtures/sdk_asset_generator.dart';

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
      soundSdkSummaryPath = _soundSdkSummaryPath(sdkDirectory);
      compilerWorkerPath = _compilerWorkerPath(sdkDirectory);

      // Copy the SDK directory into a temp directory.
      await _copy(SdkLayout.sdkDir, sdkDirectory);

      // Simulate missing sound assets.
      soundSdkFullDillPath = _soundSdkFullDillPath(sdkDirectory);
      soundSdkJsPath = _soundSdkJsPath(sdkDirectory);
      soundSdkJsMapPath = _soundSdkJsMapPath(sdkDirectory);

      _deleteIfExists(soundSdkFullDillPath);
      _deleteIfExists(soundSdkJsPath);
      _deleteIfExists(soundSdkJsMapPath);

      // Simulate missing weak assets.
      weakSdkSummaryPath = _weakSdkSummaryPath(sdkDirectory);
      weakSdkFullDillPath = _weakSdkFullDillPath(sdkDirectory);
      weakSdkJsPath = _weakSdkJsPath(sdkDirectory);
      weakSdkJsMapPath = _weakSdkJsMapPath(sdkDirectory);

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
      final configuration = SdkConfiguration.fromSdkLayout(sdkLayout);

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

String _weakSdkSummaryPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_sdk.dill');

String _soundSdkSummaryPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_outline_sound.dill');

String _weakSdkFullDillPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_platform.dill');

String _soundSdkFullDillPath(String sdkDir) =>
    p.join(sdkDir, 'lib', '_internal', 'ddc_platform_sound.dill');

String _weakSdkJsPath(String sdkDir) =>
    p.join(sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk.js');

String _soundSdkJsPath(String sdkDir) =>
    p.join(sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk_sound.js');

String _weakSdkJsMapPath(String sdkDir) =>
    p.join(sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk.js.map');

String _soundSdkJsMapPath(String sdkDir) => p.join(
    sdkDir, 'lib', 'dev_compiler', 'kernel', 'amd', 'dart_sdk_sound.js.map');

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
