// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
import 'dart:io';

import 'package:dwds/src/utilities/sdk_configuration.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

var _throwsDoesNotExistException = throwsA(
    isA<InvalidSdkConfigurationException>()
        .having((e) => '$e', 'message', contains('does not exist')));

void main() {
  group('Basic configuration', () {
    test('Can validate default configuration layout', () async {
      final defaultConfiguration =
          await DefaultSdkConfigurationProvider().configuration;
      defaultConfiguration.validateSdkDir();
      defaultConfiguration.validate();
    });

    test('Cannot validate an empty configuration layout', () async {
      final emptyConfiguration = SdkConfiguration.empty();
      expect(() => emptyConfiguration.validateSdkDir(),
          _throwsDoesNotExistException);
      expect(() => emptyConfiguration.validate(), _throwsDoesNotExistException);
    });
  });

  group('Non-standard configuration', () {
    late Directory outputDir;

    setUp(() async {
      final systemTempDir = Directory.systemTemp;
      outputDir = systemTempDir.createTempSync('foo bar');
    });

    tearDown(() async {
      await outputDir.delete(recursive: true);
    });

    test('Can validate existing configuration layout', () async {
      final defaultSdkConfiguration =
          await DefaultSdkConfigurationProvider().configuration;

      final sdkDirectory = outputDir.path;
      final sdkLayout = TestSdkLayout(sdkDirectory);
      final sdkConfiguration = TestSdkLayout.createConfiguration(sdkLayout);

      final weakSdkSummaryPath = sdkLayout.weakSummaryPath;
      final soundSdkSummaryPath = sdkLayout.soundSummaryPath;
      final summariesDir = p.dirname(soundSdkSummaryPath);

      Directory(summariesDir).createSync(recursive: true);
      File(defaultSdkConfiguration.weakSdkSummaryPath!)
          .copySync(weakSdkSummaryPath);
      File(defaultSdkConfiguration.soundSdkSummaryPath!)
          .copySync(soundSdkSummaryPath);

      final compilerWorkerPath = sdkLayout.compilerWorkerPath;
      final workerDir = p.dirname(compilerWorkerPath);

      Directory(workerDir).createSync(recursive: true);
      File(defaultSdkConfiguration.compilerWorkerPath!)
          .copySync(compilerWorkerPath);

      expect(sdkConfiguration.sdkDirectory, equals(sdkDirectory));
      expect(sdkConfiguration.weakSdkSummaryPath, equals(weakSdkSummaryPath));
      expect(sdkConfiguration.soundSdkSummaryPath, equals(soundSdkSummaryPath));
      expect(sdkConfiguration.compilerWorkerPath, equals(compilerWorkerPath));

      sdkConfiguration.validateSdkDir();
      sdkConfiguration.validate();
    });

    test('Cannot validate non-existing configuration layout', () async {
      final sdkDirectory = outputDir.path;

      final sdkLayout = TestSdkLayout(sdkDirectory);
      final sdkConfiguration = TestSdkLayout.createConfiguration(sdkLayout);

      sdkConfiguration.validateSdkDir();
      expect(() => sdkConfiguration.validate(), _throwsDoesNotExistException);
    });
  });

  group('SDK configuration', () {
    late MemoryFileSystem fs;

    final root = '/root';
    final sdkDirectory = root;

    final sdkLayout = SdkLayout.createDefault(sdkDirectory);
    final sdkConfiguration = SdkConfiguration.fromSdkLayout(sdkLayout);
    final soundSdkSummaryPath = sdkLayout.soundSummaryPath;
    final weakSdkSummaryPath = sdkLayout.weakSummaryPath;
    final compilerWorkerPath = sdkLayout.dartdevcSnapshotPath;

    setUp(() async {
      fs = MemoryFileSystem();
      await fs.directory(sdkDirectory).create(recursive: true);
      await fs.file(soundSdkSummaryPath).create(recursive: true);
      await fs.file(weakSdkSummaryPath).create(recursive: true);
      await fs.file(compilerWorkerPath).create(recursive: true);
    });

    test('Can create and validate default SDK configuration', () async {
      expect(sdkConfiguration.sdkDirectory, equals(sdkDirectory));
      expect(sdkConfiguration.soundSdkSummaryPath, equals(soundSdkSummaryPath));
      expect(sdkConfiguration.weakSdkSummaryPath, equals(weakSdkSummaryPath));
      expect(sdkConfiguration.compilerWorkerPath, equals(compilerWorkerPath));

      sdkConfiguration.validateSdkDir(fileSystem: fs);
      sdkConfiguration.validate(fileSystem: fs);
    });
  });
}

class TestSdkLayout {
  final String sdkDirectory;

  static SdkConfiguration createConfiguration(TestSdkLayout sdkLayout) =>
      SdkConfiguration(
        sdkDirectory: sdkLayout.sdkDirectory,
        soundSdkSummaryPath: sdkLayout.soundSummaryPath,
        weakSdkSummaryPath: sdkLayout.weakSummaryPath,
        compilerWorkerPath: sdkLayout.compilerWorkerPath,
      );

  TestSdkLayout(this.sdkDirectory);

  String get weakSummaryPath =>
      p.join(sdkDirectory, 'summaries', 'unsound.dill');

  String get soundSummaryPath =>
      p.join(sdkDirectory, 'summaries', 'sound.dill');

  String get compilerWorkerPath =>
      p.join(sdkDirectory, 'snapshots', 'test.snapshot');
}
