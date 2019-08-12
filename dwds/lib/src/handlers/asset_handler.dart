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
  final int _assetServerPort;
  final String _target;
  final int _applicationPort;
  final String _applicationHost;

  Handler _handler;

  AssetHandler(this._assetServerPort, this._target, this._applicationHost,
      this._applicationPort);

  Handler get handler =>
      _handler ??= proxyHandler('http://localhost:$_assetServerPort/$_target/');

  /// Returns the asset from a relative [path].
  ///
  /// For example the path `main.dart` should return the raw text value of that
  /// corresponding file.
  Future<Response> getRelativeAsset(String path) async => handler(Request(
      'GET', Uri.parse('http://$_applicationHost:$_applicationPort/$path')));
}
