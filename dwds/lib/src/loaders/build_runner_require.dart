// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../../dwds.dart';
import '../debugging/metadata/provider.dart';
import 'require.dart';
import 'strategy.dart';

/// Provides a [RequireStrategy] suitable for use with `package:build_runner`.
class BuildRunnerRequireStrategyProvider {
  final Handler _assetHandler;
  final ReloadConfiguration _configuration;
  final AssetReader _assetReader;

  RequireStrategy _requireStrategy;

  BuildRunnerRequireStrategyProvider(
      this._assetHandler, this._configuration, this._assetReader);

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
    var modules = await metadataProvider.modulePathToModule;

    var digestsPath = metadataProvider.entrypoint
        .replaceAll('.dart.bootstrap.js', '.digests');
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

  Future<Map<String, String>> _moduleProvider(
          MetadataProvider metadataProvider) async =>
      (await metadataProvider.moduleToModulePath).map((key, value) =>
          MapEntry(key, stripTopLevelDirectory(removeJsExtension(value))));

  Future<String> _moduleForServerPath(
          MetadataProvider metadataProvider, String serverPath) async =>
      (await metadataProvider.modulePathToModule).map((key, value) => MapEntry(
          stripTopLevelDirectory(key), value))[relativizePath(serverPath)];

  Future<String> _serverPathForModule(
      MetadataProvider metadataProvider, String module) async {
    var result = stripTopLevelDirectory(
        (await metadataProvider.moduleToModulePath)[module] ?? '');
    return result;
  }

  Future<String> _sourceMapPathForModule(
      MetadataProvider metadataProvider, String module) async {
    var path = (await metadataProvider.moduleToSourceMap)[module] ?? '';
    return stripTopLevelDirectory(path);
  }

  String _serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) {
      // We skip the root from which we are serving.
      return Uri.parse(appUri).pathSegments.skip(1).join('/');
    }
    return null;
  }
}
