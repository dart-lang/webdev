// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';

import 'asset_handler.dart';

/// A composition of handlers for all WebDev requests.
class WebDevHandler {
  final bool _logRequests;
  final AssetHandler _assetHandler;

  Handler _handler;

  WebDevHandler(
    this._assetHandler,
    this._logRequests,
  );

  Handler get handler {
    if (_handler == null) {
      // TODO(grouma) - add custom handler for hot reload requests.
      var pipeline = const Pipeline();
      if (_logRequests) {
        pipeline = pipeline.addMiddleware(logRequests());
      }
      _handler = pipeline.addHandler(_assetHandler.handler);
    }
    return _handler;
  }
}
