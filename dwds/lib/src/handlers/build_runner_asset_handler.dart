// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/dwds.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

import 'asset_handler.dart';

/// A handler for a build target's assets.
///
/// Proxies requests to the build runner's asset server.
class BuildRunnerAssetHandler implements AssetHandler {
  final int _applicationPort;
  final String _applicationHost;
  final LogWriter _logWriter;

  final Handler handler;

  BuildRunnerAssetHandler(
    int assetServerPort,
    String target,
    this._applicationHost,
    this._applicationPort,
    this._logWriter,
  ) : handler = proxyHandler('http://localhost:$assetServerPort/$target/');

  @override
  Future<String> dartSourceContents(String serverPath) =>
      _readResource(serverPath);

  @override
  Future<String> sourceMapContents(String serverPath) =>
      _readResource(serverPath);

  Future<String> _readResource(String path) async {
    var response = await handler(Request(
        'GET', Uri.parse('http://$_applicationHost:$_applicationPort/$path')));

    try {
      return await response.readAsString();
    } on http.ClientException {
      _logWriter(Level.WARNING, '''
      Failed to load asset at path: $path.

      Status code: ${response.statusCode}

      Headers:
      ${const JsonEncoder.withIndent('  ').convert(response.headers)}
      ''');
    }
    return null;
  }
}
