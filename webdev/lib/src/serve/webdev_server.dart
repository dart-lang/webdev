// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:dwds/asset_handler.dart';
import 'package:dwds/dwds.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_proxy/shelf_proxy.dart';

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

  final String _protocol;

  final Stream<BuildResult> buildResults;

  /// Can be null if client.js injection is disabled.
  final Dwds dwds;

  final String target;

  WebDevServer._(
    this.target,
    this._server,
    this._protocol,
    this.buildResults,
    bool autoRun, {
    this.dwds,
  }) {
    if (autoRun) {
      dwds?.connectedApps?.listen((connection) {
        connection.runMain();
      });
    }
  }

  String get host => _server.address.host;
  int get port => _server.port;
  String get protocol => _protocol;

  Future<void> stop() async {
    await dwds?.stop();
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

    Handler assetHandler;
    Dwds dwds;
    if (options.configuration.enableInjectedClient) {
      dwds = await Dwds.start(
        hostname: options.configuration.hostname,
        assetHandler: BuildRunnerAssetHandler(
          options.daemonPort,
          options.target,
          options.configuration.hostname,
          options.port,
        ),
        buildResults: filteredBuildResults,
        chromeConnection: () async =>
            (await Chrome.connectedInstance).chromeConnection,
        logWriter: logWriter,
        reloadConfiguration: options.configuration.reload,
        serveDevTools:
            options.configuration.debug || options.configuration.debugExtension,
        verbose: options.configuration.verbose,
        enableDebugExtension: options.configuration.debugExtension,
        enableDebugging: options.configuration.debug,
      );
      pipeline = pipeline.addMiddleware(dwds.middleware);
      assetHandler = dwds.handler;
    } else {
      assetHandler = proxyHandler(
          'http://localhost:${options.daemonPort}/${options.target}/');
    }

    var hostname = options.configuration.hostname;
    var tlsCertChain = options.configuration.tlsCertChain;
    var tlsCertKey = options.configuration.tlsCertKey;

    HttpServer server;
    var protocol =
        (tlsCertChain != null && tlsCertKey != null) ? 'https' : 'http';
    if (protocol == 'https') {
      var serverContext = SecurityContext()
        ..useCertificateChain(tlsCertChain)
        ..usePrivateKey(tlsCertKey);
      server =
          await HttpMultiServer.loopbackSecure(options.port, serverContext);
    } else {
      server = await HttpMultiServer.bind(hostname, options.port);
    }

    shelf_io.serveRequests(server, pipeline.addHandler(assetHandler));
    return WebDevServer._(
      options.target,
      server,
      protocol,
      filteredBuildResults,
      options.configuration.autoRun,
      dwds: dwds,
    );
  }
}
