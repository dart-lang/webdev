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
  final LogWriter _logWriter;

  RequireStrategy _requireStrategy;

  FrontendServerRequireStrategyProvider(
      this._configuration, this._assetReader, this._logWriter);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        _moduleProvider,
        _digestsProvider,
        _moduleForServerPath,
        _serverPathForModule,
        _sourceMapPathForModule,
        _serverPathForAppUri,
        _assetReader,
        _logWriter,
      );

  Future<Map<String, String>> _digestsProvider(
      MetadataProvider metadataProvider) async {
    // TODO(grouma) - provide actual digests.
    return {};
  }

  Future<Map<String, String>> _moduleProvider(
      MetadataProvider metadataProvider) async {
    var modules = await metadataProvider.modulePathToModule;

    var moduleToPath = <String, String>{};

    for (var modulePath in modules.keys) {
      // modulePath is the path including leading '/' and .js extension
      var moduleName = modules[modulePath];
      var serverPath = relativizePath(removeJsExtension(modulePath));
      moduleToPath[moduleName] = serverPath;
    }
    return moduleToPath;
  }

  Future<String> _moduleForServerPath(
      MetadataProvider metadataProvider, String serverPath) async {
    // TODO(grouma) - Fix.
    return (await metadataProvider.modulePathToModule)[serverPath];
  }

  Future<String> _serverPathForModule(
      MetadataProvider metadataProvider, String module) async {
    // TODO(grouma) - Fix.
    return (await metadataProvider.moduleToModulePath)[module];
  }

  Future<String> _sourceMapPathForModule(
      MetadataProvider metadataProvider, String module) async {
    // TODO(grouma) - Fix.
    return (await metadataProvider.moduleToSourceMap)[module];
  }

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      return Uri.parse(appUri).path.substring(1);
    }
    return null;
  }
}
