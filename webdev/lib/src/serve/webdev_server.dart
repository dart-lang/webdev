// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'handlers/asset_handler.dart';
import 'handlers/webdev_handler.dart';

class WebDevServer {
  HttpServer _server;

  WebDevServer._(this._server);

  int get port => _server.port;

  Future<void> stop() => _server.close(force: true);

  static Future<WebDevServer> start(
    String hostname,
    int port,
    int daemonPort,
    String target,
    bool logRequests,
  ) async {
    var assetHandler = AssetHandler(daemonPort, target);
    var webDevHandler = WebDevHandler(assetHandler, logRequests);
    var server = await HttpServer.bind(hostname, port);
    shelf_io.serveRequests(server, webDevHandler.handler);
    print('Serving `$target` on http://$hostname:$port');
    return WebDevServer._(server);
  }
}
