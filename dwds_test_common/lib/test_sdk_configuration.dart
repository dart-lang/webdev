// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/sdk_configuration.dart';
import 'package:logging/logging.dart';

import 'sdk_asset_generator.dart';
import 'test_sdk_layout.dart';

/// Implementation for SDK configuration for tests that can generate
/// missing assets.
///
///  - Generate SDK js, source map (normally included in flutter SDK
///    or produced by build).
class TestSdkConfigurationProvider extends SdkConfigurationProvider {
  final _logger = Logger('TestSdkConfigurationProvider');

  final bool verbose;
  final bool canaryFeatures;
  final ModuleFormat ddcModuleFormat;
  late final Directory _sdkDirectory;
  SdkConfiguration? _configuration;

  late final TestSdkLayout sdkLayout;

  TestSdkConfigurationProvider({
    this.canaryFeatures = false,
    this.verbose = false,
    this.ddcModuleFormat = ModuleFormat.amd,
  }) {
    _sdkDirectory = Directory.systemTemp.createTempSync('sdk_copy');
    sdkLayout = TestSdkLayout.createDefault(_sdkDirectory.path);
  }

  @override
  Future<SdkConfiguration> get configuration async =>
      _configuration ??= await _create();

  /// Generate missing assets in the default SDK layout.
  ///
  /// Creates a copy of the SDK directory where all the missing assets
  /// are generated. Tests using this configuration run using the copy
  /// sdk layout to make sure the actual SDK is not modified.
  Future<SdkConfiguration> _create() async {
    try {
      await copyDirectory(
        TestSdkLayout.defaultSdkDirectory,
        _sdkDirectory.path,
      );
    } catch (e, s) {
      _logger.severe('Failed to create SDK directory copy', e, s);
      dispose();
      rethrow;
    }

    try {
      final cacheDirName =
          'dwds_sdk_cache_${ddcModuleFormat.name}_$canaryFeatures';
      final cacheDir = Directory(
        p.join(Directory.systemTemp.path, cacheDirName),
      );
      final cacheJsFile = File(p.join(cacheDir.path, 'dart_sdk.js'));
      final cacheJsMapFile = File(p.join(cacheDir.path, 'dart_sdk.js.map'));

      final targetJsPath = ddcModuleFormat == ModuleFormat.amd
          ? sdkLayout.amdJsPath
          : sdkLayout.ddcJsPath;
      final targetJsMapPath = ddcModuleFormat == ModuleFormat.amd
          ? sdkLayout.amdJsMapPath
          : sdkLayout.ddcJsMapPath;

      if (cacheJsFile.existsSync() && cacheJsMapFile.existsSync()) {
        _logger.info('Found cached SDK assets in ${cacheDir.path}');
        await File(targetJsPath).create(recursive: true);
        await File(targetJsMapPath).create(recursive: true);
        await cacheJsFile.copy(targetJsPath);
        await cacheJsMapFile.copy(targetJsMapPath);
      }

      final assetGenerator = SdkAssetGenerator(
        sdkLayout: sdkLayout,
        canaryFeatures: canaryFeatures,
        verbose: verbose,
        ddcModuleFormat: ddcModuleFormat,
      );

      await assetGenerator.generateSdkAssets();

      if (!cacheJsFile.existsSync() || !cacheJsMapFile.existsSync()) {
        _logger.info('Caching SDK assets in ${cacheDir.path}');
        await cacheDir.create(recursive: true);
        final tempJs = File(p.join(cacheDir.path, 'dart_sdk.js.tmp'));
        final tempJsMap = File(p.join(cacheDir.path, 'dart_sdk.js.map.tmp'));

        await File(targetJsPath).copy(tempJs.path);
        await File(targetJsMapPath).copy(tempJsMap.path);

        await _safeRename(tempJs, cacheJsFile.path);
        await _safeRename(tempJsMap, cacheJsMapFile.path);
      }

      return TestSdkLayout.createConfiguration(sdkLayout);
    } catch (e, s) {
      _logger.severe('Failed generate missing assets', e, s);
      dispose();
      rethrow;
    }
  }

  void dispose({bool retry = true}) {
    try {
      if (_sdkDirectory.existsSync()) {
        _sdkDirectory.deleteSync(recursive: true);
      }
    } catch (e, s) {
      _logger.warning('Failed delete SDK directory copy', e, s);
      if (retry) {
        dispose(retry: false);
      }
    }
  }

  Future<void> _safeRename(File from, String to) async {
    try {
      await from.rename(to);
    } on FileSystemException {
      // Ignore if rename fails (e.g. file exists or busy on Windows).
    }
  }
}
