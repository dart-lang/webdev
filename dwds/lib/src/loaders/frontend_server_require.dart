// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../debugging/metadata/provider.dart';
import 'require.dart';
import 'strategy.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider {
  final ReloadConfiguration _configuration;
  final _moduleToPath = <String, String>{};
  final _pathToModule = <String, String>{};
  final _moduleToSourceMapPath = <String, String>{};
  RequireStrategy _requireStrategy;
  final MetadataProvider _metadataProvider;

  FrontendServerRequireStrategyProvider(
      this._configuration, this._metadataProvider);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        _moduleProvider,
        _digestsProvider,
        _moduleForServerPath,
        _serverPathForModule,
        _sourceMapPathForModule,
        _serverPathForAppUri,
      );

  Future<Map<String, String>> _digestsProvider(String entrypoint) async {
    // TODO(grouma) - provide actual digests.
    return {};
  }

  Future<Map<String, String>> _moduleProvider(String entrypoint) async {
    await _metadataProvider.initialize(entrypoint);
    var modules = await _metadataProvider.modulePathToModule;
    var sourceMaps = await _metadataProvider.moduleToSourceMap;

    _moduleToPath.clear();
    _pathToModule.clear();
    _moduleToSourceMapPath.clear();

    for (var modulePath in modules.keys) {
      // modulePath is the path including leading '/' and .js extension
      var moduleName = modules[modulePath];
      var serverPath = relativizePath(removeJsExtension(modulePath));
      var sourceMap = relativizePath(sourceMaps[moduleName]);

      _pathToModule[serverPath] = moduleName;
      _moduleToPath[moduleName] = serverPath;
      _moduleToSourceMapPath[moduleName] = sourceMap;
    }
    return _moduleToPath;
  }

  String _moduleForServerPath(String serverPath) =>
      _pathToModule[relativizePath(removeJsExtension(serverPath))];

  String _serverPathForModule(String module) =>
      addJsExtension(_moduleToPath[module]);

  String _sourceMapPathForModule(String module) =>
      _moduleToSourceMapPath[module];

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      return Uri.parse(appUri).path.substring(1);
    }
    return null;
  }
}
