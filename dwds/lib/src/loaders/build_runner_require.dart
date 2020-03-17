// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'require.dart';
import 'strategy.dart';

/// Provides a [RequireStrategy] suitable for use with `package:build_runner`.
class BuildRunnerRequireStrategyProvider {
  final _extension = '.ddc';
  final Handler _assetHandler;
  final ReloadConfiguration _configuration;
  final _serverPathToModule = <String, String>{};

  RequireStrategy _requireStrategy;

  BuildRunnerRequireStrategyProvider(this._assetHandler, this._configuration);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
        _configuration,
        _extension,
        _moduleProvider,
        _digestsProvider,
        _moduleForServerPath,
        _serverPathForModule,
      );

  Future<Map<String, String>> _digestsProvider(String entrypoint) async {
    var digestsPath = entrypoint.replaceAll('.dart.bootstrap.js', '.digests');
    var response = await _assetHandler(
        Request('GET', Uri.parse('http://foo:0000/$digestsPath')));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Could not read digests at path: $digestsPath');
    }
    var body = await response.readAsString();
    return {
      for (var entry in (json.decode(body) as Map<String, dynamic>).entries)
        entry.key.replaceAll('.ddc.js', ''): entry.value as String,
    };
  }

  /// Returns the module server path for the provided moduleId.
  ///
  ///  web/main -> main.ddc
  ///  packages/path/path -> packages/path/path.ddc
  ///
  String _serverPath(String moduleId) {
    var path = moduleId.startsWith('packages')
        ? moduleId
        : moduleId.split('/').skip(1).join('/');
    return '$path.ddc';
  }

  Future<Map<String, String>> _moduleProvider(String entrypoint) async {
    var digests = await _digestsProvider(entrypoint);
    var result = <String, String>{};
    _serverPathToModule.clear();
    for (var moduleId in digests.keys) {
      var serverPath = _serverPath(moduleId);
      _serverPathToModule[serverPath] = moduleId;
      result[moduleId] = serverPath;
    }
    return result;
  }

  String _moduleForServerPath(String serverPath) {
    if (!serverPath.endsWith('$_extension.js')) return null;
    serverPath =
        serverPath.startsWith('/') ? serverPath.substring(1) : serverPath;
    // Remove the .js from the path.
    serverPath = p.withoutExtension(serverPath);
    return _serverPathToModule[serverPath];
  }

  String _serverPathForModule(String module) => '${_serverPath(module)}.js';
}
