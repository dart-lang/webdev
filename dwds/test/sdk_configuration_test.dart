// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
import 'dart:io';

import 'package:dwds/src/utilities/sdk_configuration.dart';
import 'package:dwds/src/utilities/sdk_layout.dart';
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/utilities.dart';

var _throwsDoesNotExistException = throwsA(
    isA<InvalidSdkConfigurationException>()
        .having((e) => '$e', 'message', contains('does not exist')));

void main() {
  group('Basic configuration', () {
    test('Can validate default configuration layout', () async {
      final defaultConfiguration =
          await DefaultSdkConfigurationProvider().configuration;
      defaultConfiguration.validateSdkDir();
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
          await TestSdkConfigurationProvider().configuration;

      final sdkDirectory = outputDir.path;
      final sdkLayout = _createNonStandardLayout(sdkDirectory);

      final librariesPath = sdkLayout.librariesPath;
      final librariesDir = p.dirname(librariesPath);

      Directory(librariesDir).createSync(recursive: true);
      File(defaultSdkConfiguration.librariesPath!).copySync(librariesPath);

      final dartPath = sdkLayout.dartPath;
      final dartDir = p.dirname(dartPath);

      Directory(dartDir).createSync(recursive: true);
      File(defaultSdkConfiguration.dartPath).copySync(dartPath);

      final weakSdkSummaryPath = sdkLayout.weakSummaryPath;
      final soundSdkSummaryPath = sdkLayout.soundSummaryPath;
      final kernelDir = p.dirname(soundSdkSummaryPath);

      Directory(kernelDir).createSync(recursive: true);
      File(defaultSdkConfiguration.weakSummaryPath!)
          .copySync(weakSdkSummaryPath);
      File(defaultSdkConfiguration.soundSummaryPath!)
          .copySync(soundSdkSummaryPath);

      final compilerWorkerPath = sdkLayout.dartdevcSnapshotPath;
      final workerDir = p.dirname(compilerWorkerPath);

      Directory(workerDir).createSync(recursive: true);
      File(defaultSdkConfiguration.compilerWorkerPath!)
          .copySync(compilerWorkerPath);

      final sdkConfiguration = SdkConfiguration(sdkLayout);

      expect(sdkConfiguration.sdkDirectory, equals(sdkDirectory));
      expect(sdkConfiguration.dartPath, equals(dartPath));
      expect(sdkConfiguration.weakSummaryPath, equals(weakSdkSummaryPath));
      expect(sdkConfiguration.soundSummaryPath, equals(soundSdkSummaryPath));
      expect(sdkConfiguration.librariesPath, equals(librariesPath));
      expect(sdkConfiguration.compilerWorkerPath, equals(compilerWorkerPath));

      sdkConfiguration.validateSdkDir();
      sdkConfiguration.validate();
    });

    test('Cannot validate non-existing configuration layout', () async {
      final sdkConfiguration = SdkConfiguration(_fakeSdkLayout);
      expect(() => sdkConfiguration.validateSdkDir(),
          _throwsDoesNotExistException);
      expect(() => sdkConfiguration.validate(), _throwsDoesNotExistException);
    });
  });

  group('SDK configuration', () {
    late MemoryFileSystem fs;

    final sdkDirectory = '/root';
    final sdkLayout = SdkLayout.createDefault(sdkDirectory);

    setUp(() async {
      fs = MemoryFileSystem();
      await fs.directory(sdkDirectory).create(recursive: true);
      await fs.file(sdkLayout.soundSummaryPath).create(recursive: true);
      await fs.file(sdkLayout.weakSummaryPath).create(recursive: true);
      await fs.file(sdkLayout.dartPath).create(recursive: true);
      await fs.file(sdkLayout.librariesPath).create(recursive: true);
      await fs.file(sdkLayout.dartdevcSnapshotPath).create(recursive: true);
    });

    test('Can create and validate SDK configuration', () async {
      final configuration = SdkConfiguration(sdkLayout);

      expect(configuration.sdkDirectory, equals(sdkLayout.sdkDirectory));
      expect(configuration.dartPath, equals(sdkLayout.dartPath));
      expect(
          configuration.soundSummaryPath, equals(sdkLayout.soundSummaryPath));
      expect(configuration.weakSummaryPath, equals(sdkLayout.weakSummaryPath));

      expect(configuration.sdkDirectory, equals(sdkLayout.sdkDirectory));
      expect(
          configuration.soundSummaryPath, equals(sdkLayout.soundSummaryPath));
      expect(configuration.weakSummaryPath, equals(sdkLayout.weakSummaryPath));
      expect(configuration.librariesPath, equals(sdkLayout.librariesPath));
      expect(configuration.compilerWorkerPath,
          equals(sdkLayout.dartdevcSnapshotPath));

      configuration.validateSdkDir(fileSystem: fs);
      configuration.validate(fileSystem: fs);
    });
  });
}

final _fakeSdkLayout = SdkLayout(
  sdkDirectory: 'fakeDirectory',
  soundJsPath: 'fakeJs',
  soundJsMapPath: 'fakeJsMap',
  soundSummaryPath: 'fakeSummary',
  soundFullDillPath: 'fakeSummary',
  weakJsPath: 'fakeJs',
  weakJsMapPath: 'fakeJsMap',
  weakSummaryPath: 'fakeSummary',
  weakFullDillPath: 'fakeSummary',
  librariesPath: 'fakeLibraries',
  requireJsPath: 'fakeRequire',
  stackTraceMapperPath: 'fakeTraceMapper',
  dartPath: 'fakeDart',
  frontendServerSnapshotPath: 'fakeSnapshot',
  dartdevcSnapshotPath: 'fakeSnapshot',
  kernelWorkerSnapshotPath: 'fakeSnapshot',
);

SdkLayout _createNonStandardLayout(String sdkDirectory) => SdkLayout(
      sdkDirectory: sdkDirectory,
      soundSummaryPath: p.join(sdkDirectory, 'kernel', 'ddc_outline.dill'),
      soundFullDillPath: p.join(sdkDirectory, 'kernel', 'ddc_platform.dill'),
      soundJsPath: p.join(sdkDirectory, 'web_assets', 'dart_sdk.js'),
      soundJsMapPath: p.join(sdkDirectory, 'web_assets', 'dart_sdk.js.map'),
      weakSummaryPath:
          p.join(sdkDirectory, 'kernel', 'ddc_outline_unsound.dill'),
      weakFullDillPath:
          p.join(sdkDirectory, 'kernel', 'ddc_platform_unsound.dill'),
      weakJsPath: p.join(sdkDirectory, 'web_assets', 'dart_sdk_unsound.js'),
      weakJsMapPath:
          p.join(sdkDirectory, 'web_assets', 'dart_sdk_unsound.js.map'),
      librariesPath: p.join(sdkDirectory, 'specs', 'libraries.json'),
      requireJsPath: p.join(sdkDirectory, 'web_assets', 'require.js'),
      stackTraceMapperPath:
          p.join(sdkDirectory, 'web_assets', 'dart_stack_trace_mapper.js'),
      dartPath: p.join(sdkDirectory, 'binaries', 'dart'),
      frontendServerSnapshotPath:
          p.join(sdkDirectory, 'snapshots', 'frontend_server.dart.snapshot'),
      dartdevcSnapshotPath:
          p.join(sdkDirectory, 'snapshots', 'dartdevc.dart.snapshot'),
      kernelWorkerSnapshotPath:
          p.join(sdkDirectory, 'snapshots', 'kernel_worker.dart.snapshot'),
    );
