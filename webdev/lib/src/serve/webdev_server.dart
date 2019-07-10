// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:dwds/src/devtools.dart'; // ignore: implementation_imports
import 'package:dwds/src/handlers/asset_handler.dart'; // ignore: implementation_imports
import 'package:dwds/src/handlers/dev_handler.dart'; // ignore: implementation_imports
import 'package:dwds/src/handlers/injected_handler.dart'; // ignore: implementation_imports
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../command/configuration.dart';
import '../logging.dart';
import 'chrome.dart';
import 'handlers/favicon_handler.dart';

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

  WebDevServer._(this.target, this._server, this.devHandler, bool autoRun) {
    if (autoRun) {
      devHandler.connectedApps.listen((connection) {
        connection.runMain();
      });
    }
  }

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
    var assetHandler = AssetHandler(options.daemonPort, options.target,
        options.configuration.hostname, options.port);
    var cascade = Cascade();
    var pipeline = const Pipeline();

    if (options.configuration.logRequests) {
      pipeline = pipeline.addMiddleware(logRequests());
    }

    pipeline = pipeline
        .addMiddleware(createInjectedHandler(options.configuration.reload))
        .addMiddleware(interceptFavicon);

    var devHandler = DevHandler(
      () async => (await Chrome.connectedInstance).chromeConnection,
      // Only provide relevant build results
      buildResults.asyncMap<BuildResult>((results) => results.results
          .firstWhere((result) => result.target == options.target)),
      devTools,
      assetHandler,
      options.configuration.hostname,
      options.configuration.verbose,
      logWriter,
    );
    cascade = cascade.add(devHandler.handler).add(assetHandler.handler);

    var hostname = options.configuration.hostname;
    var server = await HttpMultiServer.bind(hostname, options.port);
    shelf_io.serveRequests(server, pipeline.addHandler(cascade.handler));
    return WebDevServer._(
        options.target, server, devHandler, options.configuration.autoRun);
  }
}
