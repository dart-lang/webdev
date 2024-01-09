// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';

void main() {
  final debug = false;

  group('Test SDK configuration provider |', () {
    setUpAll(() {
      setCurrentLogWriter(debug: debug);
    });

    test('Creates and deletes SDK directory copy', () async {
      final provider = TestSdkConfigurationProvider(verbose: debug);
      final sdkDirectory = provider.sdkLayout.sdkDirectory;
      final weakSdkSummary = provider.sdkLayout.weakSummaryPath;
      try {
        expect(sdkDirectory, _directoryExists,
            reason: 'SDK directory should be created');
        expect(weakSdkSummary, isNot(_fileExists),
            reason: 'Weak SDK summary should not be generated yet.');

        await provider.configuration;
        expect(weakSdkSummary, _fileExists,
            reason: 'Weak SDK summary should be generated');
      } finally {
        provider.dispose();
        expect(sdkDirectory, isNot(_directoryExists),
            reason: 'SDK directory copy should be deleted on dispose');
      }
    });
  });

  group('Test SDK configuration |', () {
    setCurrentLogWriter(debug: debug);
    final provider = TestSdkConfigurationProvider(verbose: debug);
    tearDownAll(provider.dispose);

    test('Can validate configuration with generated assets', () async {
      final sdkConfiguration = await provider.configuration;
      sdkConfiguration.validateSdkDir();
      sdkConfiguration.validate();
    });

    test('SDK layout exists', () async {
      await provider.configuration;
      final sdkLayout = provider.sdkLayout;

      expect(sdkLayout.sdkDirectory, _directoryExists);
      expect(sdkLayout.soundJsPath, _fileExists);
      expect(sdkLayout.soundJsMapPath, _fileExists);
      expect(sdkLayout.soundSummaryPath, _fileExists);
      expect(sdkLayout.soundFullDillPath, _fileExists);

      expect(sdkLayout.weakJsPath, _fileExists);
      expect(sdkLayout.weakJsMapPath, _fileExists);
      expect(sdkLayout.weakSummaryPath, _fileExists);
      expect(sdkLayout.weakFullDillPath, _fileExists);

      expect(sdkLayout.requireJsPath, _fileExists);
      expect(sdkLayout.stackTraceMapperPath, _fileExists);

      expect(sdkLayout.dartPath, _fileExists);
      expect(sdkLayout.dartAotRuntimePath, _fileExists);
      expect(sdkLayout.frontendServerSnapshotPath, _fileExists);
      expect(sdkLayout.dartdevcSnapshotPath, _fileExists);
      expect(sdkLayout.kernelWorkerSnapshotPath, _fileExists);
      expect(sdkLayout.devToolsDirectory, _directoryExists);
    });
  });
}

Matcher _fileExists =
    predicate((String path) => File(path).existsSync(), 'File exists');

Matcher _directoryExists = predicate(
    (String path) => Directory(path).existsSync(), 'Directory exists');
