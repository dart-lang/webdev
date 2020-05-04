// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import '../../dwds.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider {
  final ReloadConfiguration _configuration;
  final Iterable<String> _modules;
  final _extension = '.lib.js';
  RequireStrategy _requireStrategy;

  FrontendServerRequireStrategyProvider(this._modules, this._configuration);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        _extension,
        _moduleProvider,
        _digestsProvider,
        _moduleForServerPath,
        _serverPathForModule,
        _serverPathForAppUri,
      );

  Future<Map<String, String>> _digestsProvider(String entrypoint) async {
    // TODO(grouma) - provide actual digests.
    return {};
  }

  Future<Map<String, String>> _moduleProvider(String entrypoint) async {
    final modulePaths = <String, String>{};
    for (var module in _modules) {
      module = module.startsWith('/') ? module.substring(1) : module;
      var name = module.replaceAll('.lib.js', '');
      var path = module.replaceAll('.js', '');
      modulePaths[name] = path;
    }
    return modulePaths;
  }

  String _moduleForServerPath(String serverPath) {
    if (serverPath.endsWith('.lib.js')) {
      serverPath =
          serverPath.startsWith('/') ? serverPath.substring(1) : serverPath;
      return serverPath.replaceAll('.lib.js', '');
    }
    return null;
  }

  String _serverPathForModule(String module) => '$module.lib.js';

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      return Uri.parse(appUri).path.substring(1);
    }
    return null;
  }
}
