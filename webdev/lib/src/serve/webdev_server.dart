// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:dwds/dwds.dart';
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
  final String target;
  final Dwds dwds;
  final Stream<BuildResult> buildResults;

  WebDevServer._(
    this.target,
    this._server,
    this.dwds,
    this.buildResults,
    bool autoRun,
  ) {
    if (autoRun) {
      dwds.connectedApps.listen((connection) {
        connection.runMain();
      });
    }
  }

  String get host => _server.address.host;
  int get port => _server.port;

  Future<void> stop() async {
    await dwds.stop();
    await _server.close(force: true);
  }

  static Future<WebDevServer> start(
      ServerOptions options, Stream<BuildResults> buildResults) async {
    var pipeline = const Pipeline();

    if (options.configuration.logRequests) {
      pipeline = pipeline.addMiddleware(logRequests());
    }

    pipeline = pipeline.addMiddleware(interceptFavicon);

    // Only provide relevant build results
    var filteredBuildResults = buildResults.asyncMap<BuildResult>((results) =>
        results.results
            .firstWhere((result) => result.target == options.target));

    var dwds = await Dwds.start(
      hostname: options.configuration.hostname,
      applicationPort: options.port,
      applicationTarget: options.target,
      assetServerPort: options.daemonPort,
      buildResults: filteredBuildResults,
      chromeConnection: () async =>
          (await Chrome.connectedInstance).chromeConnection,
      logWriter: logWriter,
      reloadConfiguration: options.configuration.reload,
      serveDevTools: options.configuration.debug,
      verbose: options.configuration.verbose,
      enableDebugExtension: options.configuration.debugExtension,
    );

    var hostname = options.configuration.hostname;
    var server = await HttpMultiServer.bind(hostname, options.port);
    shelf_io.serveRequests(server, pipeline.addHandler(dwds.handler));
    return WebDevServer._(
      options.target,
      server,
      dwds,
      filteredBuildResults,
      options.configuration.autoRun,
    );
  }
}
