// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart' as daemon;
import 'package:dds/devtools_server.dart';
import 'package:dwds/data/build_result.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/sdk_configuration.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

import '../command/configuration.dart';
import '../util.dart';
import 'chrome.dart';
import 'handlers/favicon_handler.dart';

Logger _logger = Logger('WebDevServer');

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
  final http.Client _client;
  final String _protocol;

  final Stream<BuildResult> buildResults;

  /// Can be null if client.js injection is disabled.
  final Dwds? dwds;

  final ExpressionCompilerService? ddcService;

  final String target;

  WebDevServer._(
    this.target,
    this._server,
    this._client,
    this._protocol,
    this.buildResults,
    bool autoRun, {
    this.dwds,
    this.ddcService,
  }) {
    if (autoRun) {
      dwds?.connectedApps.listen((connection) {
        connection.runMain();
      });
    }
  }

  String get host => _server.address.host;
  int get port => _server.port;
  String get protocol => _protocol;

  Future<void> stop() async {
    await dwds?.stop();
    await ddcService?.stop();
    await _server.close(force: true);
    _client.close();
  }

  static Future<WebDevServer> start(
      ServerOptions options, Stream<daemon.BuildResults> buildResults) async {
    var pipeline = const Pipeline();

    if (options.configuration.logRequests) {
      pipeline = pipeline.addMiddleware(logRequests());
    }

    pipeline = pipeline.addMiddleware(interceptFavicon);

    // Only provide relevant build results
    final filteredBuildResults = buildResults.asyncMap<BuildResult>((results) {
      final result = results.results
          .firstWhere((result) => result.target == options.target);
      switch (result.status) {
        case daemon.BuildStatus.started:
          return BuildResult((b) => b.status = BuildStatus.started);
        case daemon.BuildStatus.failed:
          return BuildResult((b) => b.status = BuildStatus.failed);
        case daemon.BuildStatus.succeeded:
          return BuildResult((b) => b.status = BuildStatus.succeeded);
        default:
          break;
      }
      throw StateError('Unexpected Daemon build result: $result');
    });

    var cascade = Cascade();
    final client = IOClient(HttpClient()
      ..maxConnectionsPerHost = 200
      ..idleTimeout = const Duration(seconds: 30)
      ..connectionTimeout = const Duration(seconds: 30));
    final assetHandler = proxyHandler(
        'http://localhost:${options.daemonPort}/${options.target}/',
        client: client);

    Dwds? dwds;
    ExpressionCompilerService? ddcService;
    if (options.configuration.enableInjectedClient) {
      final assetReader = ProxyServerAssetReader(
        options.daemonPort,
        root: options.target,
      );

      // TODO(https://github.com/flutter/devtools/issues/5350): Figure out how
      // to determine the build settings from the build.
      // Can we save build metadata in build_web_compilers and and read it in
      // the load strategy?
      final buildSettings = BuildSettings(
        appEntrypoint:
            Uri.parse('org-dartlang-app:///${options.target}/main.dart'),
        canaryFeatures: options.configuration.canaryFeatures,
        isFlutterApp: false,
        experiments: options.configuration.experiments,
      );

      final loadStrategy = BuildRunnerRequireStrategyProvider(
        assetHandler,
        options.configuration.reload,
        assetReader,
        buildSettings,
      ).strategy;

      if (options.configuration.enableExpressionEvaluation) {
        ddcService = ExpressionCompilerService(
          options.configuration.hostname,
          options.port,
          verbose: options.configuration.verbose,
          sdkConfigurationProvider: const DefaultSdkConfigurationProvider(),
        );
      }
      final shouldServeDevTools =
          options.configuration.debug || options.configuration.debugExtension;

      final debugSettings = DebugSettings(
        enableDebugExtension: options.configuration.debugExtension,
        enableDebugging: options.configuration.debug,
        spawnDds: !options.configuration.disableDds,
        expressionCompiler: ddcService,
        devToolsLauncher: shouldServeDevTools
            ? (String hostname) async {
                final server = await DevToolsServer().serveDevTools(
                  hostname: hostname,
                  enableStdinCommands: false,
                  customDevToolsPath: devToolsPath,
                );
                return DevTools(server!.address.host, server.port, server);
              }
            : null,
      );

      final appMetadata = AppMetadata(
        hostname: options.configuration.hostname,
      );

      final toolConfiguration = ToolConfiguration(
          loadStrategy: loadStrategy,
          debugSettings: debugSettings,
          appMetadata: appMetadata);
      dwds = await Dwds.start(
        toolConfiguration: toolConfiguration,
        assetReader: assetReader,
        buildResults: filteredBuildResults,
        chromeConnection: () async =>
            (await Chrome.connectedInstance).chromeConnection,
      );
      pipeline = pipeline.addMiddleware(dwds.middleware);
      cascade = cascade.add(dwds.handler);
      cascade = cascade.add(assetHandler);
    } else {
      cascade = cascade.add(assetHandler);
    }

    final hostname = options.configuration.hostname;
    final tlsCertChain = options.configuration.tlsCertChain ?? '';
    final tlsCertKey = options.configuration.tlsCertKey ?? '';

    HttpServer server;
    var protocol =
        (tlsCertChain.isNotEmpty && tlsCertKey.isNotEmpty) ? 'https' : 'http';
    if (protocol == 'https') {
      final serverContext = SecurityContext()
        ..useCertificateChain(tlsCertChain)
        ..usePrivateKey(tlsCertKey);
      server =
          await HttpMultiServer.loopbackSecure(options.port, serverContext);
    } else {
      server = await HttpMultiServer.bind(hostname, options.port);
    }

    serveHttpRequests(server, pipeline.addHandler(cascade.handler), (e, s) {
      _logger.warning('Error serving requests', e, s);
    });

    return WebDevServer._(
      options.target,
      server,
      client,
      protocol,
      filteredBuildResults,
      options.configuration.autoRun,
      dwds: dwds,
      ddcService: ddcService,
    );
  }
}
