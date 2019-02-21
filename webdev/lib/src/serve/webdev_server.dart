// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'handlers/asset_handler.dart';
import 'handlers/build_results_handler.dart';
import 'middlewares/reload_middleware.dart';

class ServerOptions {
  final String hostname;
  final int port;
  final String target;
  final int daemonPort;
  final bool liveReload;
  final bool hotRestart;
  final bool logRequests;

  ServerOptions(
    this.hostname,
    this.port,
    this.target,
    this.daemonPort,
    this.liveReload,
    this.hotRestart,
    this.logRequests,
  );
}

class WebDevServer {
  HttpServer _server;

  WebDevServer._(this._server);

  String get host => _server.address.host;
  int get port => _server.port;

  Future<void> stop() => _server.close(force: true);

  static Future<WebDevServer> start(
    ServerOptions options,
    Stream<BuildResults> buildResults,
  ) async {
    var assetHandler = AssetHandler(options.daemonPort, options.target);
    var cascade = Cascade();
    var pipeline = const Pipeline();

    if (options.logRequests) {
      pipeline = pipeline.addMiddleware(logRequests());
    }

    if (options.liveReload || options.hotRestart) {
      if (options.liveReload) {
        pipeline = pipeline.addMiddleware(injectLiveReloadClientCode);
      }

      if (options.hotRestart) {
        pipeline = pipeline.addMiddleware(injectHotRestartClientCode);
      }

      var buildResultsHandler = BuildResultsHandler(
          // Only provide relevant build results
          buildResults.asyncMap<BuildResult>((results) => results.results
              .firstWhere((result) => result.target == options.target)));
      cascade = cascade.add(buildResultsHandler.handler);
    }

    cascade = cascade.add(assetHandler.handler);

    var server = await HttpServer.bind(options.hostname, options.port);
    shelf_io.serveRequests(server, pipeline.addHandler(cascade.handler));
    print('Serving `${options.target}` on '
        'http://${options.hostname}:${options.port}');
    return WebDevServer._(server);
  }
}
