// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build_daemon/data/build_status.dart' as daemon;
import 'package:dwds/data/build_result.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

Handler _interceptFavicon(Handler handler) {
  return (request) async {
    if (request.url.pathSegments.isNotEmpty &&
        request.url.pathSegments.last == 'favicon.ico') {
      return Response.ok('');
    }
    return handler(request);
  };
}

class TestServer {
  final HttpServer _server;
  final String target;
  final Dwds dwds;
  final Stream<BuildResult> buildResults;
  final AssetReader assetReader;

  TestServer._(
    this.target,
    this._server,
    this.dwds,
    this.buildResults,
    bool autoRun,
    this.assetReader,
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

  static Future<TestServer> start(
      String hostname,
      int port,
      Handler assetHandler,
      AssetReader assetReader,
      RequireStrategy strategy,
      MetadataProvider metadataProvider,
      String target,
      Stream<daemon.BuildResults> buildResults,
      Future<ChromeConnection> Function() chromeConnection,
      bool serveDevTools,
      bool enableDebugExtension,
      bool autoRun,
      bool enableDebugging,
      bool useSse,
      UrlEncoder urlEncoder,
      bool restoreBreakpoints,
      ExpressionCompiler expressionCompiler,
      LogWriter logWriter) async {
    var pipeline = const Pipeline();

    pipeline = pipeline.addMiddleware(_interceptFavicon);

    var filteredBuildResults = buildResults.asyncMap<BuildResult>((results) {
      var result =
          results.results.firstWhere((result) => result.target == target);
      switch (result.status) {
        case daemon.BuildStatus.started:
          return BuildResult((b) => b.status = BuildStatus.started);
        case daemon.BuildStatus.failed:
          return BuildResult((b) => b.status = BuildStatus.failed);
        case daemon.BuildStatus.succeeded:
          return BuildResult((b) => b.status = BuildStatus.succeeded);
      }
      throw StateError('Unexpected Daemon build result: $result');
    });

    var dwds = await Dwds.start(
      assetReader: assetReader,
      buildResults: filteredBuildResults,
      chromeConnection: chromeConnection,
      logWriter: logWriter,
      loadStrategy: strategy,
      metadataProvider: metadataProvider,
      serveDevTools: serveDevTools,
      enableDebugExtension: enableDebugExtension,
      enableDebugging: enableDebugging,
      useSseForDebugProxy: useSse,
      useSseForDebugBackend: useSse,
      hostname: hostname,
      verbose: true,
      urlEncoder: urlEncoder,
      expressionCompiler: expressionCompiler,
    );

    var server = await HttpMultiServer.bind('localhost', port);
    shelf_io.serveRequests(
        server,
        pipeline
            .addMiddleware(dwds.middleware)
            .addHandler(Cascade().add(dwds.handler).add(assetHandler).handler));
    return TestServer._(
      target,
      server,
      dwds,
      filteredBuildResults,
      autoRun,
      assetReader,
    );
  }
}
