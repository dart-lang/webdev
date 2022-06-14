// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.9

import 'package:path/path.dart' as p;

import '../debugging/metadata/provider.dart';
import '../loaders/strategy.dart';
import '../readers/asset_reader.dart';
import '../services/expression_compiler.dart';
import 'require.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider {
  final ReloadConfiguration _configuration;
  final AssetReader _assetReader;
  final Future<Map<String, String>> Function() _digestsProvider;
  final String _basePath;

  RequireStrategy _requireStrategy;

  FrontendServerRequireStrategyProvider(this._configuration, this._assetReader,
      this._digestsProvider, String basePath)
      : _basePath = basePathForServerUri(basePath);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        _moduleProvider,
        (_) => _digestsProvider(),
        _moduleForServerPath,
        _serverPathForModule,
        _sourceMapPathForModule,
        _serverPathForAppUri,
        _moduleInfoForProvider,
        _assetReader,
      );

  String _removeBasePath(String path) =>
      path.startsWith(_basePath) ? path.substring(_basePath.length) : null;

  String _addBasePath(String serverPath) =>
      _basePath == null || _basePath.isEmpty
          ? relativizePath(serverPath)
          : '$_basePath/${relativizePath(serverPath)}';

  Future<Map<String, String>> _moduleProvider(
          MetadataProvider metadataProvider) async =>
      (await metadataProvider.moduleToModulePath).map((key, value) =>
          MapEntry(key, relativizePath(removeJsExtension(value))));

  Future<String> _moduleForServerPath(
      MetadataProvider metadataProvider, String serverPath) async {
    final modulePathToModule = await metadataProvider.modulePathToModule;
    return modulePathToModule[_removeBasePath(serverPath)];
  }

  Future<String> _serverPathForModule(
          MetadataProvider metadataProvider, String module) async =>
      _addBasePath((await metadataProvider.moduleToModulePath)[module] ?? '');

  Future<String> _sourceMapPathForModule(
          MetadataProvider metadataProvider, String module) async =>
      _addBasePath((await metadataProvider.moduleToSourceMap)[module] ?? '');

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      return _addBasePath(Uri.parse(appUri).path);
    }
    return null;
  }

  Future<Map<String, ModuleInfo>> _moduleInfoForProvider(
      MetadataProvider metadataProvider) async {
    final modules = await metadataProvider.moduleToModulePath;
    final result = <String, ModuleInfo>{};
    for (var module in modules.keys) {
      final modulePath = modules[module];
      result[module] = ModuleInfo(
          // TODO: Save locations of full kernel files in ddc metadata.
          // Issue: https://github.com/dart-lang/sdk/issues/43684
          p.setExtension(modulePath, '.full.dill'),
          p.setExtension(modulePath, '.dill'));
    }
    return result;
  }
}
