// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.9

import 'dart:io';

import 'package:path/path.dart' as p;

class InvalidSdkConfigurationException implements Exception {
  final String message;

  InvalidSdkConfigurationException([this.message]);

  @override
  String toString() {
    var message = this.message;
    if (message == null) return 'Invalid SDK configuration';
    return 'Invalid SDK configuration: $message';
  }
}

/// Interface describing the SDK layout.
///
/// Note: Supports lazily populated configurations.
/// Call [validate] method to make sure the files in the
/// configuration layout exist before reading the files.
abstract class SdkConfigurationInterface {
  Future<String> get sdkDirectory;
  Future<String> get unsoundSdkSummaryPath;
  Future<String> get soundSdkSummaryPath;
  Future<String> get librariesPath;
  Future<String> get compilerWorkerPath;

  Future<Uri> get sdkDirectoryUri =>
      sdkDirectory.then((value) => value == null ? null : p.toUri(value));

  Future<Uri> get soundSdkSummaryUri => soundSdkSummaryPath
      .then((value) => value == null ? null : p.toUri(value));

  Future<Uri> get unsoundSdkSummaryUri => unsoundSdkSummaryPath
      .then((value) => value == null ? null : p.toUri(value));

  Future<Uri> get librariesUri =>
      librariesPath.then((value) => value == null ? null : p.toUri(value));

  /// Note: has to be ///file: Uri to run in an isolate.
  Future<Uri> get compilerWorkerUri => compilerWorkerPath
      .then((value) => value == null ? null : p.toUri(p.absolute(value)));

  /// Throws [InvalidSdkConfigurationException] if configuration does not
  /// exist on disk.
  Future<void> validate() async {
    await validateSdkDir();

    var libraries = await librariesPath;
    if (libraries == null || !File(libraries).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Libraries spec $libraries does not exist');
    }

    var unsoundSdkSummary = await unsoundSdkSummaryPath;
    if (unsoundSdkSummary == null || !File(unsoundSdkSummary).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $unsoundSdkSummary does not exist');
    }

    var soundSdkSummary = await soundSdkSummaryPath;
    if (soundSdkSummary == null || !File(soundSdkSummary).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk summary $soundSdkSummary does not exist');
    }

    var compilerWorker = await compilerWorkerPath;
    if (compilerWorker == null || !File(compilerWorker).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Compiler worker $compilerWorker does not exist');
    }
  }

  /// Throws [InvalidSdkConfigurationException] if SDK root does not
  /// exist on the disk.
  Future<void> validateSdkDir() async {
    var sdkDir = await sdkDirectory;
    if (sdkDir == null || !Directory(sdkDir).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Sdk directory $sdkDir does not exist');
    }
  }
}

/// Implementation for the default SDK configuration layout.
class SdkConfiguration extends SdkConfigurationInterface {
  final String _sdkDirectory;
  final String _unsoundSdkSummaryPath;
  final String _soundSdkSummaryPath;
  final String _librariesPath;
  final String _compilerWorkerPath;

  SdkConfiguration({
    String sdkDirectory,
    String unsoundSdkSummaryPath,
    String soundSdkSummaryPath,
    String librariesPath,
    String compilerWorkerPath,
  })  : _sdkDirectory = sdkDirectory,
        _unsoundSdkSummaryPath = unsoundSdkSummaryPath,
        _soundSdkSummaryPath = soundSdkSummaryPath,
        _librariesPath = librariesPath,
        _compilerWorkerPath = compilerWorkerPath;

  @override
  Future<String> get sdkDirectory async => _sdkDirectory;

  @override
  Future<String> get unsoundSdkSummaryPath async => _unsoundSdkSummaryPath;

  @override
  Future<String> get soundSdkSummaryPath async => _soundSdkSummaryPath;

  @override
  Future<String> get librariesPath async => _librariesPath;

  @override
  Future<String> get compilerWorkerPath async => _compilerWorkerPath;

  /// Create and validate configuration matching the default SDK layout.
  factory SdkConfiguration.standard() {
    final binDir = p.dirname(Platform.resolvedExecutable);
    final sdkDir = p.dirname(binDir);

    if (sdkDir == null || !Directory(sdkDir).existsSync()) {
      throw InvalidSdkConfigurationException(
          'Could not detect default SDK configuration. '
          'Directory $sdkDir does not exist.');
    }

    var configuration = SdkConfiguration(
      sdkDirectory: sdkDir,
      unsoundSdkSummaryPath: p.join(sdkDir, 'lib', '_internal', 'ddc_sdk.dill'),
      soundSdkSummaryPath:
          p.join(sdkDir, 'lib', '_internal', 'ddc_outline_sound.dill'),
      librariesPath: p.join(sdkDir, 'lib', 'libraries.json'),
      compilerWorkerPath: p.join(binDir, 'snapshots', 'dartdevc.dart.snapshot'),
    );

    configuration.validate();
    return configuration;
  }
}
