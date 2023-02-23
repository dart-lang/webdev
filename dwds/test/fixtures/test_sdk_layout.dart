// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO:(annagrin) Move to a test_common package.
import 'package:dwds/src/utilities/sdk_configuration.dart';
import 'package:path/path.dart' as p;

/// Test Dart SDK layout.
///
/// Contains definition of the default SDK layout required for tests.
/// We keep all the path constants in one place for ease of update.
class TestSdkLayout {
  static final defaultSdkDirectory = SdkLayout.defaultSdkDirectory;
  static TestSdkLayout defaultSdkLayout =
      TestSdkLayout.createDefault(defaultSdkDirectory);
  static SdkConfiguration defaultSdkConfiguration =
      createConfiguration(defaultSdkLayout);

  factory TestSdkLayout.createDefault(String sdkDirectory) =>
      TestSdkLayout.createDefaultFromSdkLayout(
          SdkLayout.createDefault(sdkDirectory));

  factory TestSdkLayout.createDefaultFromSdkLayout(SdkLayout sdkLayout) =>
      TestSdkLayout(
        sdkDirectory: sdkLayout.sdkDirectory,
        soundSummaryPath: sdkLayout.soundSummaryPath,
        soundFullDillPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          '_internal',
          'ddc_platform.dill',
        ),
        soundJsPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk.js',
        ),
        soundJsMapPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk.js.map',
        ),
        weakSummaryPath: sdkLayout.weakSummaryPath,
        weakFullDillPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          '_internal',
          'ddc_platform_unsound.dill',
        ),
        weakJsPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk_unsound.js',
        ),
        weakJsMapPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk_unsound.js.map',
        ),
        requireJsPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'amd',
          'require.js',
        ),
        stackTraceMapperPath: p.join(
          sdkLayout.sdkDirectory,
          'lib',
          'dev_compiler',
          'web',
          'dart_stack_trace_mapper.js',
        ),
        dartPath: p.join(sdkLayout.sdkDirectory, 'bin', 'dart'),
        frontendServerSnapshotPath: p.join(
          sdkLayout.sdkDirectory,
          'bin',
          'snapshots',
          'frontend_server.dart.snapshot',
        ),
        dartdevcSnapshotPath: sdkLayout.dartdevcSnapshotPath,
        kernelWorkerSnapshotPath: p.join(
          sdkLayout.sdkDirectory,
          'bin',
          'snapshots',
          'kernel_worker.dart.snapshot',
        ),
      );

  final String sdkDirectory;

  String get soundJsFileName => p.basename(soundJsPath);
  String get soundJsMapFileName => p.basename(soundJsMapPath);
  String get soundSummaryFileName => p.basename(soundSummaryPath);
  String get soundFullDillFileName => p.basename(soundFullDillPath);

  final String soundJsPath;
  final String soundJsMapPath;
  final String soundSummaryPath;
  final String soundFullDillPath;

  String get weakJsFileName => p.basename(weakJsPath);
  String get weakJsMapFileName => p.basename(weakJsMapPath);
  String get weakSummaryFileName => p.basename(weakSummaryPath);
  String get weakFullDillFileName => p.basename(weakFullDillPath);

  final String weakJsPath;
  final String weakJsMapPath;
  final String weakSummaryPath;
  final String weakFullDillPath;

  final String requireJsPath;
  final String stackTraceMapperPath;

  final String dartPath;
  final String frontendServerSnapshotPath;
  final String dartdevcSnapshotPath;
  final String kernelWorkerSnapshotPath;

  const TestSdkLayout({
    required this.sdkDirectory,
    required this.soundJsPath,
    required this.soundJsMapPath,
    required this.soundSummaryPath,
    required this.soundFullDillPath,
    required this.weakJsPath,
    required this.weakJsMapPath,
    required this.weakSummaryPath,
    required this.weakFullDillPath,
    required this.requireJsPath,
    required this.stackTraceMapperPath,
    required this.dartPath,
    required this.frontendServerSnapshotPath,
    required this.dartdevcSnapshotPath,
    required this.kernelWorkerSnapshotPath,
  });

  /// Creates configuration from sdk layout.
  static SdkConfiguration createConfiguration(TestSdkLayout sdkLayout) =>
      SdkConfiguration(
        sdkDirectory: sdkLayout.sdkDirectory,
        weakSdkSummaryPath: sdkLayout.weakSummaryPath,
        soundSdkSummaryPath: sdkLayout.soundSummaryPath,
        compilerWorkerPath: sdkLayout.dartdevcSnapshotPath,
      );
}
