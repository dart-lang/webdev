// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;

/// SDK layout.
///
/// Contains definition of the default SDK layout.
/// We keep all the path constants in one place for ease of update.
///
/// TODO(annagrin): Restructure to move out test code and minimize
/// requirements for creating an SDK configuration.
/// Issue: https://github.com/dart-lang/webdev/issues/1901
class SdkLayout {
  static final defaultSdkDirectory =
      p.dirname(p.dirname(Platform.resolvedExecutable));
  static final defaultSdkLayout = createDefault(defaultSdkDirectory);

  static SdkLayout createDefault(String sdkDirectory) => SdkLayout(
        sdkDirectory: sdkDirectory,
        soundSummaryPath: p.join(
          sdkDirectory,
          'lib',
          '_internal',
          'ddc_outline.dill',
        ),
        soundFullDillPath: p.join(
          sdkDirectory,
          'lib',
          '_internal',
          'ddc_platform.dill',
        ),
        soundJsPath: p.join(
          sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk.js',
        ),
        soundJsMapPath: p.join(
          sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk.js.map',
        ),
        weakSummaryPath: p.join(
          sdkDirectory,
          'lib',
          '_internal',
          'ddc_outline_unsound.dill',
        ),
        weakFullDillPath: p.join(
          sdkDirectory,
          'lib',
          '_internal',
          'ddc_platform_unsound.dill',
        ),
        weakJsPath: p.join(
          sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk_unsound.js',
        ),
        weakJsMapPath: p.join(
          sdkDirectory,
          'lib',
          'dev_compiler',
          'kernel',
          'amd',
          'dart_sdk_unsound.js.map',
        ),
        librariesPath: p.join(
          sdkDirectory,
          'lib',
          'libraries.json',
        ),
        requireJsPath: p.join(
          sdkDirectory,
          'lib',
          'dev_compiler',
          'amd',
          'require.js',
        ),
        stackTraceMapperPath: p.join(
          sdkDirectory,
          'lib',
          'dev_compiler',
          'web',
          'dart_stack_trace_mapper.js',
        ),
        dartPath: p.join(sdkDirectory, 'bin', 'dart'),
        frontendServerSnapshotPath: p.join(
          sdkDirectory,
          'bin',
          'snapshots',
          'frontend_server.dart.snapshot',
        ),
        dartdevcSnapshotPath: p.join(
          sdkDirectory,
          'bin',
          'snapshots',
          'dartdevc.dart.snapshot',
        ),
        kernelWorkerSnapshotPath: p.join(
          sdkDirectory,
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

  final String librariesPath;
  final String requireJsPath;
  final String stackTraceMapperPath;

  final String dartPath;
  final String frontendServerSnapshotPath;
  final String dartdevcSnapshotPath;
  final String kernelWorkerSnapshotPath;

  SdkLayout({
    required this.sdkDirectory,
    required this.soundJsPath,
    required this.soundJsMapPath,
    required this.soundSummaryPath,
    required this.soundFullDillPath,
    required this.weakJsPath,
    required this.weakJsMapPath,
    required this.weakSummaryPath,
    required this.weakFullDillPath,
    required this.librariesPath,
    required this.requireJsPath,
    required this.stackTraceMapperPath,
    required this.dartPath,
    required this.frontendServerSnapshotPath,
    required this.dartdevcSnapshotPath,
    required this.kernelWorkerSnapshotPath,
  });
}
