// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@TestOn('vm')
import 'dart:io';

import 'package:dwds/src/utilities/sdk_configuration.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

var _throwsDoesNotExistException = throwsA(
    isA<InvalidSdkConfigurationException>()
        .having((e) => '$e', 'message', contains('does not exist')));

void main() {
  group('Basic configuration', () {
    test('Can validate default configuration layout', () async {
      var defaultConfiguration = SdkConfiguration.standard();
      await defaultConfiguration.validateSdkDir();
      await defaultConfiguration.validate();
    });

    test('Cannot validate an empty configuration layout', () async {
      var emptyConfiguration = SdkConfiguration();
      await expectLater(
          emptyConfiguration.validateSdkDir(), _throwsDoesNotExistException);
      await expectLater(
          emptyConfiguration.validate(), _throwsDoesNotExistException);
    });
  });

  group('Non-standard configuration', () {
    Directory outputDir;

    setUp(() async {
      var systemTempDir = Directory.systemTemp;
      outputDir = systemTempDir.createTempSync('foo bar');
    });

    tearDown(() async {
      await outputDir?.delete(recursive: true);
    });

    test('Can validate existing configuration layout', () async {
      var defaultSdkConfiguration = SdkConfiguration.standard();

      var sdkDirectory = outputDir.path;
      var librariesDir = p.join(sdkDirectory, 'specs');
      var librariesPath = p.join(librariesDir, 'libraries.json');

      Directory(librariesDir).createSync(recursive: true);
      File(await defaultSdkConfiguration.librariesPath).copySync(librariesPath);

      var summariesDir = p.join(sdkDirectory, 'summaries');
      var unsoundSdkSummaryPath = p.join(summariesDir, 'ddc_sdk.dill');
      var soundSdkSummaryPath = p.join(summariesDir, 'ddc_outline_sound.dill');

      Directory(summariesDir).createSync(recursive: true);
      File(await defaultSdkConfiguration.unsoundSdkSummaryPath)
          .copySync(unsoundSdkSummaryPath);
      File(await defaultSdkConfiguration.soundSdkSummaryPath)
          .copySync(soundSdkSummaryPath);

      var workerDir = p.join(sdkDirectory, 'snapshots');
      var compilerWorkerPath = p.join(workerDir, 'dartdevc.dart.snapshot');

      Directory(workerDir).createSync(recursive: true);
      File(await defaultSdkConfiguration.compilerWorkerPath)
          .copySync(compilerWorkerPath);

      var sdkConfiguration = SdkConfiguration(
        sdkDirectory: sdkDirectory,
        soundSdkSummaryPath: soundSdkSummaryPath,
        unsoundSdkSummaryPath: unsoundSdkSummaryPath,
        librariesPath: librariesPath,
        compilerWorkerPath: compilerWorkerPath,
      );

      expect(await sdkConfiguration.sdkDirectory, equals(sdkDirectory));
      expect(await sdkConfiguration.unsoundSdkSummaryPath,
          equals(unsoundSdkSummaryPath));
      expect(await sdkConfiguration.soundSdkSummaryPath,
          equals(soundSdkSummaryPath));
      expect(await sdkConfiguration.librariesPath, equals(librariesPath));
      expect(await sdkConfiguration.compilerWorkerPath,
          equals(compilerWorkerPath));

      await expectLater(sdkConfiguration.validateSdkDir(), completes);
      await expectLater(sdkConfiguration.validate(), completes);
    });

    test('Cannot validate non-existing configuration layout', () async {
      var sdkDir = outputDir.path;
      var librariesDir = p.join(sdkDir, 'fakespecs');
      var librariesPath = p.join(librariesDir, 'libraries.json');
      var summariesDir = p.join(sdkDir, 'fakesummaries');
      var unsoundSdkSummaryPath = p.join(summariesDir, 'ddc_sdk.dill');
      var soundSdkSummaryPath = p.join(summariesDir, 'ddc_outline_sound.dill');
      var workerDir = p.join(sdkDir, 'fakesnapshots');
      var compilerWorkerPath = p.join(workerDir, 'dartdevc.dart.snapshot');

      var sdkConfiguration = SdkConfiguration(
        sdkDirectory: sdkDir,
        soundSdkSummaryPath: soundSdkSummaryPath,
        unsoundSdkSummaryPath: unsoundSdkSummaryPath,
        librariesPath: librariesPath,
        compilerWorkerPath: compilerWorkerPath,
      );

      await expectLater(sdkConfiguration.validateSdkDir(), completes);
      await expectLater(
          sdkConfiguration.validate(), _throwsDoesNotExistException);
    });
  });
}
