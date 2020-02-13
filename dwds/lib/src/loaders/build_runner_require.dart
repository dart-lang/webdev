// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'require.dart';
import 'strategy.dart';

/// Provides a [RequireStrategy] suitable for use with `package:build_runner`.
class BuildRunnerRequireStrategyProvider {
  final Handler _assetHandler;
  final ReloadConfiguration _configuration;

  RequireStrategy _requireStrategy;

  BuildRunnerRequireStrategyProvider(this._assetHandler, this._configuration);

  RequireStrategy get strategy => _requireStrategy ??= RequireStrategy(
      _configuration, '.ddc', _moduleProvider, _digestsProvider);

  Future<Map<String, String>> _digestsProvider(String entrypoint) async {
    var digestsPath = entrypoint.replaceAll('.dart.bootstrap.js', '.digests');
    var response = await _assetHandler(
        Request('GET', Uri.parse('http://foo:0000/$digestsPath')));
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('Could not read digests at path: $digestsPath');
    }
    var body = await response.readAsString();
    var digests =
        (json.decode(body) as Map<String, dynamic>).cast<String, String>();
    return digests;
  }

  String _modulePathFor(String digestPath) => (digestPath.startsWith('packages')
          ? digestPath
          : digestPath.split('/').skip(1).join('/'))
      .replaceAll('.js', '');
  Future<Map<String, String>> _moduleProvider(String entrypoint) async {
    var digests = await _digestsProvider(entrypoint);
    var result = <String, String>{};
    for (var digestPath in digests.keys) {
      var moduleName = digestPath.replaceAll('.ddc.js', '');
      result[moduleName] = _modulePathFor(digestPath);
    }
    return result;
  }
}
