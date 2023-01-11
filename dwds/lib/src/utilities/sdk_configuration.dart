// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;

import 'sdk_layout.dart';

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

/// SDK configuration.
///
/// Provides helpers to convert paths to uris that work on all platforms.
///
/// Call [validate] method to make sure the files in the configuration
/// layout exist before reading the files.
class SdkConfiguration {
  static final defaultSdkLayout = SdkLayout.defaultSdkLayout;
  static final defaultConfiguration = SdkConfiguration(defaultSdkLayout);

  SdkLayout? sdkLayout;

  SdkConfiguration(this.sdkLayout);

  SdkConfiguration.empty() : this(null);

  static Uri? _toUri(String? path) => path == null ? null : p.toUri(path);
  static Uri? _toAbsoluteUri(String? path) =>
      path == null ? null : p.toUri(p.absolute(path));

  String get dartPath => sdkLayout!.dartPath;
  String? get sdkDirectory => sdkLayout?.sdkDirectory;
  String? get soundSummaryPath => sdkLayout?.soundSummaryPath;
  String? get weakSummaryPath => sdkLayout?.weakSummaryPath;
  String? get librariesPath => sdkLayout?.librariesPath;
  String? get compilerWorkerPath => sdkLayout?.dartdevcSnapshotPath;

  Uri? get sdkDirectoryUri => _toUri(sdkDirectory);
  Uri? get soundSummaryUri => _toUri(soundSummaryPath);
  Uri? get weakSummaryUri => _toUri(weakSummaryPath);
  Uri? get librariesUri => _toUri(librariesPath);

  /// Note: has to be ///file: Uri to run in an isolate.
  Uri? get compilerWorkerUri => _toAbsoluteUri(compilerWorkerPath);

  /// Throws [InvalidSdkConfigurationException] if configuration does not
  /// exist on disk.
  void validate({FileSystem fileSystem = const LocalFileSystem()}) {
    validateSdkDir(fileSystem: fileSystem);
    validateDartExecutable(fileSystem: fileSystem);
    validateSummaries(fileSystem: fileSystem);
    validateLibrariesSpec(fileSystem: fileSystem);
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

  /// Throws [InvalidSdkConfigurationException] if SDK root does not
  /// exist on the disk.
  void validateDartExecutable(
      {FileSystem fileSystem = const LocalFileSystem()}) {
    if (!fileSystem.file(dartPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Dart executable $dartPath does not exist');
    }
  }

  void validateSummaries({FileSystem fileSystem = const LocalFileSystem()}) {
    validateSoundSummaries(fileSystem: fileSystem);
    validateWeakSummaries(fileSystem: fileSystem);
  }

  void validateWeakSummaries(
      {FileSystem fileSystem = const LocalFileSystem()}) {
    if (weakSummaryPath == null ||
        !fileSystem.file(weakSummaryPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $weakSummaryPath does not exist');
    }
  }

  void validateSoundSummaries(
      {FileSystem fileSystem = const LocalFileSystem()}) {
    if ((soundSummaryPath == null ||
        !fileSystem.file(soundSummaryPath).existsSync())) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $soundSummaryPath does not exist');
    }
  }

  void validateLibrariesSpec(
      {FileSystem fileSystem = const LocalFileSystem()}) {
    if (librariesPath == null || !fileSystem.file(librariesPath).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Libraries spec $librariesPath does not exist');
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
