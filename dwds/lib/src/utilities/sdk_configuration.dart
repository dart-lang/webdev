// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

/// Dart SDK layout.
///
/// Contains definition of the default SDK layout.
/// We keep all the path constants in one place for ease of update.
class SdkLayout {
  static final defaultSdkDirectory =
      p.dirname(p.dirname(Platform.resolvedExecutable));
  static final SdkLayout defaultSdkLayout =
      SdkLayout.createDefault(defaultSdkDirectory);

  final String sdkDirectory;
  final String soundSummaryPath;
  final String weakSummaryPath;
  final String dartdevcSnapshotPath;

  SdkLayout.createDefault(String sdkDirectory)
      : this(
          sdkDirectory: sdkDirectory,
          soundSummaryPath: p.join(
            sdkDirectory,
            'lib',
            '_internal',
            'ddc_outline.dill',
          ),
          weakSummaryPath: p.join(
            sdkDirectory,
            'lib',
            '_internal',
            'ddc_outline_unsound.dill',
          ),
          dartdevcSnapshotPath: p.join(
            sdkDirectory,
            'bin',
            'snapshots',
            'dartdevc.dart.snapshot',
          ),
        );

  const SdkLayout({
    required this.sdkDirectory,
    required this.soundSummaryPath,
    required this.weakSummaryPath,
    required this.dartdevcSnapshotPath,
  });
}

/// Dart SDK configuration.
///
/// Provides helpers to convert paths to uris that work on all platforms.
///
class SdkConfiguration {
  static final defaultSdkLayout = SdkLayout.defaultSdkLayout;
  static final defaultConfiguration =
      SdkConfiguration.fromSdkLayout(SdkLayout.defaultSdkLayout);

  final String? sdkDirectory;
  final String? weakSdkSummaryPath;
  final String? soundSdkSummaryPath;
  final String? compilerWorkerPath;

  const SdkConfiguration({
    this.sdkDirectory,
    this.weakSdkSummaryPath,
    this.soundSdkSummaryPath,
    this.compilerWorkerPath,
  });

  const SdkConfiguration.empty() : this();

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
        'Sdk directory $sdkDirectory does not exist',
      );
    }
  }

  void validateSummaries({FileSystem fileSystem = const LocalFileSystem()}) {
    validateSoundSummaries(fileSystem: fileSystem);
    validateWeakSummaries(fileSystem: fileSystem);
  }

  void validateWeakSummaries({
    FileSystem fileSystem = const LocalFileSystem(),
  }) {
    if (weakSdkSummaryPath == null ||
        !fileSystem.file(weakSdkSummaryPath).existsSync()) {
      throw InvalidSdkConfigurationException(
        'Sdk summary $weakSdkSummaryPath does not exist',
      );
    }
  }

  void validateSoundSummaries({
    FileSystem fileSystem = const LocalFileSystem(),
  }) {
    if ((soundSdkSummaryPath == null ||
        !fileSystem.file(soundSdkSummaryPath).existsSync())) {
      throw InvalidSdkConfigurationException(
        'Sdk summary $soundSdkSummaryPath does not exist',
      );
    }
  }

  void validateCompilerWorker({
    FileSystem fileSystem = const LocalFileSystem(),
  }) {
    if (compilerWorkerPath == null ||
        !fileSystem.file(compilerWorkerPath).existsSync()) {
      throw InvalidSdkConfigurationException(
        'Compiler worker $compilerWorkerPath does not exist',
      );
    }
  }
}

class DefaultSdkConfigurationProvider extends SdkConfigurationProvider {
  const DefaultSdkConfigurationProvider();

  @override
  Future<SdkConfiguration> get configuration async =>
      SdkConfiguration.defaultConfiguration;
}
