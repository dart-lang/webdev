// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:path/path.dart' as p;
import '../../dwds.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider {
  final ReloadConfiguration _configuration;
  final Map<String, String> _moduleToPath = {};
  final Map<String, String> _pathToModule = {};
  final Map<String, String> _moduleToSourceMapPath = {};
  final _extension = '.lib.js';
  RequireStrategy _requireStrategy;
  final MetadataProvider _metadataProvider;

  FrontendServerRequireStrategyProvider(
      this._configuration, this._metadataProvider);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        _extension,
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

    for (var modulePath in modules.keys) {
      var name = modules[modulePath];
      var path = _convertToJSRequirePath(modulePath);
      _moduleToPath[name] = path;
      _pathToModule[path] = name;
      var sourceMaps = await _metadataProvider.moduleToSourceMap;
      _moduleToSourceMapPath[name] = _stripTopLevelDirectory(sourceMaps[name]);
    }
    return _moduleToPath;
  }

  // /web/modulename.lib.js => web/modulename.lib
  String _convertToJSRequirePath(String modulePath) =>
      _stripTopLevelDirectory(p.withoutExtension(modulePath));

  String _stripTopLevelDirectory(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  String _moduleForServerPath(String serverPath) =>
      _pathToModule[_convertToJSRequirePath(serverPath)];

  String _serverPathForModule(String module) => '${_moduleToPath[module]}.js';

  String _sourceMapPathForModule(String module) =>
      _moduleToSourceMapPath[module];

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      return Uri.parse(appUri).path.substring(1);
    }
    return null;
  }
}
