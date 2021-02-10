// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:path/path.dart' as p;

import '../../dwds.dart';
import 'require.dart';
import 'strategy.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider {
  final ReloadConfiguration _configuration;
  final AssetReader _assetReader;
  final Future<Map<String, String>> Function() _digestsProvider;

  RequireStrategy _requireStrategy;

  FrontendServerRequireStrategyProvider(
      this._configuration, this._assetReader, this._digestsProvider);

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

  Future<Map<String, String>> _moduleProvider(
          MetadataProvider metadataProvider) async =>
      (await metadataProvider.moduleToModulePath).map((key, value) =>
          MapEntry(key, relativizePath(removeJsExtension(value))));

  Future<String> _moduleForServerPath(
          MetadataProvider metadataProvider, String serverPath) async =>
      (await metadataProvider.modulePathToModule)[serverPath];

  Future<String> _serverPathForModule(
          MetadataProvider metadataProvider, String module) async =>
      (await metadataProvider.moduleToModulePath)[module] ?? '';

  Future<String> _sourceMapPathForModule(
      MetadataProvider metadataProvider, String module) async {
    var path = (await metadataProvider.moduleToSourceMap)[module] ?? '';
    return relativizePath(path);
  }

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      return Uri.parse(appUri).path.substring(1);
    }
    return null;
  }

  Future<Map<String, ModuleInfo>> _moduleInfoForProvider(
      MetadataProvider metadataProvider) async {
    var modules = await metadataProvider.moduleToModulePath;
    var result = <String, ModuleInfo>{};
    for (var module in modules.keys) {
      var modulePath = modules[module];
      result[module] = ModuleInfo(
          // TODO: Save locations of full kernel files in ddc metadata.
          // Issue: https://github.com/dart-lang/sdk/issues/43684
          p.setExtension(modulePath, '.full.dill'),
          p.setExtension(modulePath, '.dill'));
    }
    return result;
  }
}
