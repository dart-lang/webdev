// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

/// A handler for a build target's assets.
///
/// Proxies requests to the build daemon asset server.
class AssetHandler {
  final int _daemonPort;
  final String _target;

  Handler _handler;

  AssetHandler(
    this._daemonPort,
    this._target,
  );

  Handler get handler {
    _handler ??= proxyHandler('http://localhost:$_daemonPort/$_target/');
    return _handler;
  }
}
