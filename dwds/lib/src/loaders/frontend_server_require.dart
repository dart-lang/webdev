// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../../dwds.dart';
import 'require.dart';
import 'strategy.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider {
  final ReloadConfiguration _configuration;
  final AssetReader _assetReader;

  RequireStrategy _requireStrategy;

  FrontendServerRequireStrategyProvider(this._configuration, this._assetReader);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        _moduleProvider,
        _digestsProvider,
        _moduleForServerPath,
        _serverPathForModule,
        _sourceMapPathForModule,
        _serverPathForAppUri,
        _assetReader,
      );

  Future<Map<String, String>> _digestsProvider(
      MetadataProvider metadataProvider) async {
    // TODO(grouma) - provide actual digests.
    return {};
  }

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
}
