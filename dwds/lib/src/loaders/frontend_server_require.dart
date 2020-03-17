// Copyright 2020 The Dart Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:dwds/dwds.dart';

/// Provides a [RequireStrategy] suitable for use with Frontend Server.
class FrontendServerRequireStrategyProvider {
  final ReloadConfiguration _configuration;
  final Iterable<String> _modules;
  RequireStrategy _requireStrategy;

  FrontendServerRequireStrategyProvider(this._modules, this._configuration);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        '.lib.js',
        _moduleProvider,
        _digestsProvider,
        _moduleForServerPath,
        _serverPathForModule,
      );

  Future<Map<String, String>> _digestsProvider(String entrypoint) async {
    return {};
  }

  Future<Map<String, String>> _moduleProvider(String entrypoint) async {
    final modulePaths = <String, String>{};
    for (var module in _modules) {
      // We are currently 'guessing' module names from js module paths,
      // which is not reliable.
      // example:
      //  module: /web/main.dart.lib.js'
      //  name: web/main.dart
      //  path: web/main.dart.lib
      // Note: This is a temporary workaround until we solve inconsistencies
      // in different configurations by introducing module name and path
      // translation interfaces between compiler, asset server, and the
      // debugger.
      // TODO(annagrin): module interface
      // [issue #910](https://github.com/dart-lang/webdev/issues/910)
      module = module.startsWith('/') ? module.substring(1) : module;
      var name = module.replaceAll('.lib.js', '');
      var path = module.replaceAll('.js', '');
      modulePaths[name] = path;
    }
    return modulePaths;
  }

  String _moduleForServerPath(String serverPath) {
    return '';
  }

  String _serverPathForModule(String module) {
    return '';
  }
}
