// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';

import '../middlewares/reload_middleware.dart';
import 'asset_handler.dart';
import 'build_results_handler.dart';

/// A composition of handlers for all WebDev requests.
class WebDevHandler {
  final bool _logRequests;
  final AssetHandler _assetHandler;
  final BuildResultsHandler _buildResultsHandler;

  Handler _handler;

  WebDevHandler(
    this._assetHandler,
    this._buildResultsHandler,
    this._logRequests,
  );

  Handler get handler {
    if (_handler == null) {
      var cascade = Cascade();
      var pipeline = const Pipeline();
      if (_logRequests) {
        pipeline = pipeline.addMiddleware(logRequests());
      }
      if (_buildResultsHandler != null) {
        pipeline = pipeline.addMiddleware(injectLiveReloadClientCode);
        cascade = cascade.add(_buildResultsHandler.handler);
      }
      cascade = cascade.add(_assetHandler.handler);
      _handler = pipeline.addHandler(cascade.handler);
    }
    return _handler;
  }
}
