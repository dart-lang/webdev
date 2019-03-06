// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../command/configuration.dart';
import 'debugger/devtools.dart';
import 'handlers/asset_handler.dart';
import 'handlers/dev_handler.dart';
import 'middlewares/injected_middleware.dart';

class ServerOptions {
  final Configuration configuration;
  final int port;
  final String target;
  final int daemonPort;

  ServerOptions(
    this.configuration,
    this.port,
    this.target,
    this.daemonPort,
  );
}

class WebDevServer {
  HttpServer _server;
  DevHandler _devHandler;

  WebDevServer._(this._server, this._devHandler);

  String get host => _server.address.host;
  int get port => _server.port;

  Future<void> stop() async {
    await _devHandler.close();
    await _server.close(force: true);
  }

  static Future<WebDevServer> start(
    ServerOptions options,
    Stream<BuildResults> buildResults,
    Future<DevTools> devtoolsFuture,
  ) async {
    var assetHandler = AssetHandler(options.daemonPort, options.target);
    var cascade = Cascade();
    var pipeline = const Pipeline();

    if (options.configuration.logRequests) {
      pipeline = pipeline.addMiddleware(logRequests());
    }

    pipeline = pipeline
        .addMiddleware(createInjectedHandler(options.configuration.reload));

    var devHandler = DevHandler(
      // Only provide relevant build results
      buildResults.asyncMap<BuildResult>((results) => results.results
          .firstWhere((result) => result.target == options.target)),
      devtoolsFuture,
    );
    cascade = cascade.add(devHandler.handler).add(assetHandler.handler);

    var server =
        await HttpServer.bind(options.configuration.hostname, options.port);
    shelf_io.serveRequests(server, pipeline.addHandler(cascade.handler));
    print('Serving `${options.target}` on '
        'http://${options.configuration.hostname}:${options.port}');
    return WebDevServer._(server, devHandler);
  }
}
