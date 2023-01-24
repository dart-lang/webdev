// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

class InvalidSdkConfigurationException implements Exception {
  final String? message;

  InvalidSdkConfigurationException([this.message]);

  @override
  String toString() {
    final message = this.message;
    if (message == null) return 'Invalid SDK configuration';
    return 'Invalid SDK configuration: $message';
  }
}

/// SDK configuration provider interface.
///
/// Supports lazily populated configurations by allowing to create
/// configuration asynchronously.
abstract class SdkConfigurationProvider {
  const SdkConfigurationProvider();

  Future<SdkConfiguration> get configuration;
}

/// Sdk layout.
///
/// Contains definition of the default SDK layout.
/// We keep all the path constants in one place for ease of update.
class SdkLayout {
  static final sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
  static final defaultSdkLayout = createDefault(sdkDir);

  static SdkLayout createDefault(String sdkDirectory) {
    final sdkJsWeakFileName = 'dart_sdk.js';
    final sdkJsMapWeakFileName = 'dart_sdk.js.map';
    final sdkJsSoundFileName = 'dart_sdk_sound.js';
    final sdkJsMapSoundFileName = 'dart_sdk_sound.js.map';
    final sdkSummarySoundFileName = 'ddc_outline_sound.dill';
    final sdkSummaryWeakFileName = 'ddc_sdk.dill';
    final sdkFullDillSoundFileName = 'ddc_platform_sound.dill';
    final sdkFullDillWeakFileName = 'ddc_platform.dill';

    final sdkSummaryDirectory = p.join(sdkDirectory, 'lib', '_internal');
    final sdkJsDirectory =
        p.join(sdkDirectory, 'lib', 'dev_compiler', 'kernel', 'amd');

    final soundSummaryPath =
        p.join(sdkSummaryDirectory, sdkSummarySoundFileName);
    final soundFullDillPath =
        p.join(sdkSummaryDirectory, sdkFullDillSoundFileName);
    final soundJsPath = p.join(sdkJsDirectory, sdkJsSoundFileName);
    final soundJsMapPath = p.join(sdkJsDirectory, sdkJsMapSoundFileName);

    final weakSummaryPath = p.join(sdkSummaryDirectory, sdkSummaryWeakFileName);
    final weakFullDillPath =
        p.join(sdkSummaryDirectory, sdkFullDillWeakFileName);
    final weakJsPath = p.join(sdkJsDirectory, sdkJsWeakFileName);
    final weakJsMapPath = p.join(sdkJsDirectory, sdkJsMapWeakFileName);

    final librariesPath = p.join(sdkDirectory, 'lib', 'libraries.json');
    final dartdevcSnapshotPath =
        p.join(sdkDirectory, 'bin', 'snapshots', 'dartdevc.dart.snapshot');
    final kernelWorkerSnapshotPath =
        p.join(sdkDirectory, 'bin', 'snapshots', 'kernel_worker.dart.snapshot');

    return SdkLayout(
      sdkJsWeakFileName: sdkJsWeakFileName,
      sdkJsMapWeakFileName: sdkJsMapWeakFileName,
      sdkJsSoundFileName: sdkJsSoundFileName,
      sdkJsMapSoundFileName: sdkJsMapSoundFileName,
      sdkSummarySoundFileName: sdkSummarySoundFileName,
      sdkSummaryWeakFileName: sdkSummaryWeakFileName,
      sdkFullDillSoundFileName: sdkFullDillSoundFileName,
      sdkFullDillWeakFileName: sdkFullDillWeakFileName,
      sdkDirectory: sdkDirectory,
      soundSummaryPath: soundSummaryPath,
      soundFullDillPath: soundFullDillPath,
      soundJsPath: soundJsPath,
      soundJsMapPath: soundJsMapPath,
      weakSummaryPath: weakSummaryPath,
      weakFullDillPath: weakFullDillPath,
      weakJsPath: weakJsPath,
      weakJsMapPath: weakJsMapPath,
      librariesPath: librariesPath,
      dartdevcSnapshotPath: dartdevcSnapshotPath,
      kernelWorkerSnapshotPath: kernelWorkerSnapshotPath,
    );
  }

  final String sdkJsWeakFileName;
  final String sdkJsMapWeakFileName;
  final String sdkJsSoundFileName;
  final String sdkJsMapSoundFileName;
  final String sdkSummarySoundFileName;
  final String sdkSummaryWeakFileName;
  final String sdkFullDillSoundFileName;
  final String sdkFullDillWeakFileName;

  final String sdkDirectory;

  final String soundSummaryPath;
  final String soundFullDillPath;
  final String soundJsPath;
  final String soundJsMapPath;

  final String weakSummaryPath;
  final String weakFullDillPath;
  final String weakJsPath;
  final String weakJsMapPath;

  final String librariesPath;

  final String dartdevcSnapshotPath;
  final String kernelWorkerSnapshotPath;

  SdkLayout({
    required this.sdkJsWeakFileName,
    required this.sdkJsMapWeakFileName,
    required this.sdkJsSoundFileName,
    required this.sdkJsMapSoundFileName,
    required this.sdkSummarySoundFileName,
    required this.sdkSummaryWeakFileName,
    required this.sdkFullDillSoundFileName,
    required this.sdkFullDillWeakFileName,
    required this.sdkDirectory,
    required this.soundSummaryPath,
    required this.soundFullDillPath,
    required this.soundJsPath,
    required this.soundJsMapPath,
    required this.weakSummaryPath,
    required this.weakFullDillPath,
    required this.weakJsPath,
    required this.weakJsMapPath,
    required this.librariesPath,
    required this.dartdevcSnapshotPath,
    required this.kernelWorkerSnapshotPath,
  });
}

/// Data class describing the SDK layout.
///
/// Provides helpers to convert paths to uris that work on all platforms.
///
/// Call [validate] method to make sure the files in the configuration
/// layout exist before reading the files.
class SdkConfiguration {
  static final defaultSdkLayout = SdkLayout.defaultSdkLayout;
  static final defaultConfiguration =
      SdkConfiguration.fromSdkLayout(defaultSdkLayout);

  String? sdkDirectory;
  String? weakSdkSummaryPath;
  String? soundSdkSummaryPath;
  String? compilerWorkerPath;

  SdkConfiguration({
    this.sdkDirectory,
    this.weakSdkSummaryPath,
    this.soundSdkSummaryPath,
    this.compilerWorkerPath,
  });

  SdkConfiguration.empty() : this();

  SdkConfiguration.fromSdkLayout(SdkLayout sdkLayout)
      : this(
          sdkDirectory: sdkLayout.sdkDirectory,
          weakSdkSummaryPath: sdkLayout.weakSummaryPath,
          soundSdkSummaryPath: sdkLayout.soundSummaryPath,
          compilerWorkerPath: sdkLayout.dartdevcSnapshotPath,
        );

  static Uri? _toUri(String? path) => path == null ? null : p.toUri(path);
  static Uri? _toAbsoluteUri(String? path) =>
      path == null ? null : p.toUri(p.absolute(path));

  Uri? get sdkDirectoryUri => _toUri(sdkDirectory);
  Uri? get soundSdkSummaryUri => _toUri(soundSdkSummaryPath);
  Uri? get weakSdkSummaryUri => _toUri(weakSdkSummaryPath);

  /// Note: has to be ///file: Uri to run in an isolate.
  Uri? get compilerWorkerUri => _toAbsoluteUri(compilerWorkerPath);

  /// Throws [InvalidSdkConfigurationException] if configuration does not
  /// exist on disk.
  void validate({FileSystem fileSystem = const LocalFileSystem()}) {
    validateSdkDir(fileSystem: fileSystem);
    validateSummaries(fileSystem: fileSystem);
    validateCompilerWorker(fileSystem: fileSystem);
  }

  /// Throws [InvalidSdkConfigurationException] if SDK root does not
  /// exist on the disk.
  void validateSdkDir({FileSystem fileSystem = const LocalFileSystem()}) {
    if (sdkDirectory == null ||
        !fileSystem.directory(sdkDirectory).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk directory $sdkDirectory does not exist');
    }
  }

  void validateSummaries({FileSystem fileSystem = const LocalFileSystem()}) {
    validateSoundSummaries(fileSystem: fileSystem);
    validateWeakSummaries(fileSystem: fileSystem);
  }

  void validateWeakSummaries(
      {FileSystem fileSystem = const LocalFileSystem()}) {
    if (weakSdkSummaryPath == null ||
        !fileSystem.file(weakSdkSummaryPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $weakSdkSummaryPath does not exist');
    }
  }

  void validateSoundSummaries(
      {FileSystem fileSystem = const LocalFileSystem()}) {
    if ((soundSdkSummaryPath == null ||
        !fileSystem.file(soundSdkSummaryPath).existsSync())) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $soundSdkSummaryPath does not exist');
    }
  }

  void validateCompilerWorker(
      {FileSystem fileSystem = const LocalFileSystem()}) {
    if (compilerWorkerPath == null ||
        !fileSystem.file(compilerWorkerPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Compiler worker $compilerWorkerPath does not exist');
    }
  }
}

class DefaultSdkConfigurationProvider extends SdkConfigurationProvider {
  const DefaultSdkConfigurationProvider();

  @override
  Future<SdkConfiguration> get configuration async =>
      SdkConfiguration.defaultConfiguration;
}
