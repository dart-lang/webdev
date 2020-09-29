// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../debugging/metadata/provider.dart';
import 'require.dart';
import 'strategy.dart';

/// Provides a [RequireStrategy] suitable for use with `package:build_runner`.
class BuildRunnerRequireStrategyProvider {
  final Handler _assetHandler;
  final ReloadConfiguration _configuration;
  final _serverPathToModule = <String, String>{};
  final _moduleToServerPath = <String, String>{};
  final _moduleToSourceMapPath = <String, String>{};
  final MetadataProvider _metadataProvider;

  RequireStrategy _requireStrategy;

  BuildRunnerRequireStrategyProvider(
      this._assetHandler, this._configuration, this._metadataProvider);

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
    await _metadataProvider.initialize(entrypoint, update: false);
    var modules = await _metadataProvider.modulePathToModule;

    var digestsPath = entrypoint.replaceAll('.dart.bootstrap.js', '.digests');
    var response = await _assetHandler(
        Request('GET', Uri.parse('http://foo:0000/$digestsPath')));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Could not read digests at path: $digestsPath');
    }
    var body = await response.readAsString();
    return {
      for (var entry in (json.decode(body) as Map<String, dynamic>).entries)
        modules[entry.key]: entry.value as String,
    };
  }

  // /main.ddc.js -> main.ddc.js
  String _normalizeServerPath(String path) =>
      path.startsWith('/') ? path.substring(1) : path;

  String _removeJsExtension(String path) =>
      p.extension(path) == '.js' ? p.withoutExtension(path) : path;

  String _addJsExtension(String path) => '$path.js';

  // web/main.ddc.js -> main.ddc.js
  // packages/test/test.dart.js -> packages/test/test.dart.js
  String _stripTopLevelDirectory(String path) =>
      path.startsWith('packages') ? path : path.split('/').skip(1).join('/');

  Future<Map<String, String>> _moduleProvider(String entrypoint) async {
    await _metadataProvider.initialize(entrypoint, update: true);
    var modules = await _metadataProvider.modulePathToModule;
    var sourceMaps = await _metadataProvider.moduleToSourceMap;

    _serverPathToModule.clear();
    _moduleToServerPath.clear();
    _moduleToSourceMapPath.clear();

    for (var path in modules.keys) {
      // path is the path including top level directory and .js extension
      var serverPath = _stripTopLevelDirectory(_removeJsExtension(path));
      var moduleName = modules[path];
      var sourceMap = sourceMaps[moduleName];

      _serverPathToModule[serverPath] = moduleName;
      _moduleToServerPath[moduleName] = serverPath;
      _moduleToSourceMapPath[moduleName] = _stripTopLevelDirectory(sourceMap);
    }
    return _moduleToServerPath;
  }

  String _moduleForServerPath(String serverPath) {
    serverPath = _normalizeServerPath(_removeJsExtension(serverPath));
    return _serverPathToModule[serverPath];
  }

  String _serverPathForModule(String module) =>
      _addJsExtension(_moduleToServerPath[module]);

  String _sourceMapPathForModule(String module) =>
      _moduleToSourceMapPath[module];

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      // We skip the root from which we are serving.
      return Uri.parse(appUri).pathSegments.skip(1).join('/');
    }
    return null;
  }
}
