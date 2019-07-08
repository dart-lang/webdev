// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

/// A handler for a build target's assets.
///
/// Proxies requests to the build daemon asset server.
class AssetHandler {
  final int _daemonPort;
  final String _target;
  final int _applicationPort;
  final String _applicationHost;

  Handler _handler;

  AssetHandler(this._daemonPort, this._target, this._applicationHost,
      this._applicationPort);

  Handler get handler =>
      _handler ??= proxyHandler('http://localhost:$_daemonPort/$_target/');

  /// Returns the asset from a relative [path].
  ///
  /// For example the path `main.dart` should return the raw text value of that
  /// corresponding file.
  Future<String> getRelativeAsset(String path) async {
    var response = await handler(Request(
        'GET', Uri.parse('http://$_applicationHost:$_applicationPort/$path')));
    return await response.readAsString();
  }
}
