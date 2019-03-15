// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:uuid/uuid.dart';

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
  final HttpServer _server;
  final DevHandler devHandler;
  final String target;
  final String appId;

  WebDevServer._(this.target, this._server, this.devHandler, this.appId);

  String get host => _server.address.host;
  int get port => _server.port;

  Future<void> stop() async {
    await devHandler.close();
    await _server.close(force: true);
  }

  static Future<WebDevServer> start(
    ServerOptions options,
    Stream<BuildResults> buildResults,
    DevTools devTools,
  ) async {
    var appId = Uuid().v1() as String;
    var assetHandler = AssetHandler(options.daemonPort, options.target,
        options.configuration.hostname, options.port);
    var cascade = Cascade();
    var pipeline = const Pipeline();

    if (options.configuration.logRequests) {
      pipeline = pipeline.addMiddleware(logRequests());
    }

    pipeline = pipeline.addMiddleware(
        createInjectedHandler(options.configuration.reload, appId));

    var devHandler = DevHandler(
      // Only provide relevant build results
      buildResults.asyncMap<BuildResult>((results) => results.results
          .firstWhere((result) => result.target == options.target)),
      devTools,
      assetHandler,
      options.configuration.hostname,
    );
    cascade = cascade.add(devHandler.handler).add(assetHandler.handler);

    var server =
        await HttpServer.bind(options.configuration.hostname, options.port);
    shelf_io.serveRequests(server, pipeline.addHandler(cascade.handler));
    return WebDevServer._(options.target, server, devHandler, appId);
  }
}
