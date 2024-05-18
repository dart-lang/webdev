// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:dwds/expression_compiler.dart';
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

  group('Test SDK configuration | DDC with DDC modules |', () {
    setCurrentLogWriter(debug: debug);
    final provider = TestSdkConfigurationProvider(
        verbose: debug, ddcModuleFormat: ModuleFormat.ddc);
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
      expect(sdkLayout.soundDdcJsPath, _fileExists);
      expect(sdkLayout.soundDdcJsMapPath, _fileExists);
      expect(sdkLayout.soundSummaryPath, _fileExists);
      expect(sdkLayout.soundFullDillPath, _fileExists);

      expect(sdkLayout.weakDdcJsPath, _fileExists);
      expect(sdkLayout.weakDdcJsMapPath, _fileExists);
      expect(sdkLayout.weakSummaryPath, _fileExists);
      expect(sdkLayout.weakFullDillPath, _fileExists);

      expect(sdkLayout.ddcModuleLoaderJsPath, _fileExists);
      expect(sdkLayout.stackTraceMapperPath, _fileExists);

      expect(sdkLayout.dartPath, _fileExists);
      expect(sdkLayout.frontendServerSnapshotPath, _fileExists);
      expect(sdkLayout.dartdevcSnapshotPath, _fileExists);
      expect(sdkLayout.kernelWorkerSnapshotPath, _fileExists);
      expect(sdkLayout.devToolsDirectory, _directoryExists);
    });
  });

  group('Test SDK configuration | DDC with AMD modules |', () {
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
      expect(sdkLayout.soundAmdJsPath, _fileExists);
      expect(sdkLayout.soundAmdJsMapPath, _fileExists);
      expect(sdkLayout.soundSummaryPath, _fileExists);
      expect(sdkLayout.soundFullDillPath, _fileExists);

      expect(sdkLayout.weakAmdJsPath, _fileExists);
      expect(sdkLayout.weakAmdJsMapPath, _fileExists);
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
