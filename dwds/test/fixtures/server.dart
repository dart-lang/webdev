// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build_daemon/data/build_status.dart' as daemon;
import 'package:dwds/asset_handler.dart';
import 'package:dwds/data/build_result.dart';
import 'package:dwds/dwds.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

class TestServer {
  final HttpServer _server;
  final String target;
  final Dwds dwds;
  final Stream<BuildResult> buildResults;

  TestServer._(
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

  static Future<TestServer> start(
      String hostname,
      int port,
      int assetServerPort,
      String target,
      Stream<daemon.BuildResults> buildResults,
      Future<ChromeConnection> Function() chromeConnection,
      ReloadConfiguration reloadConfiguration,
      bool serveDevTools,
      bool enableDebugExtension,
      bool autoRun,
      bool enableDebugging,
      UrlEncoder urlEncoder,
      bool restoreBreakpoints) async {
    var pipeline = const Pipeline();

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

    var assetHandler =
        BuildRunnerAssetHandler(assetServerPort, target, 'localhost', port);

    var dwds = await Dwds.start(
      assetHandler: assetHandler,
      buildResults: filteredBuildResults,
      chromeConnection: chromeConnection,
      logWriter: (level, message) => printOnFailure(message),
      reloadConfiguration: reloadConfiguration,
      serveDevTools: serveDevTools,
      enableDebugExtension: enableDebugExtension,
      enableDebugging: enableDebugging,
      hostname: hostname,
      verbose: true,
      urlEncoder: urlEncoder,
      // ignore: deprecated_member_use_from_same_package
      restoreBreakpoints: restoreBreakpoints,
    );

    var server = await HttpMultiServer.bind('localhost', port);
    shelf_io.serveRequests(
        server,
        pipeline.addMiddleware(dwds.middleware).addHandler(
            Cascade().add(dwds.handler).add(assetHandler.handler).handler));
    return TestServer._(
      target,
      server,
      dwds,
      filteredBuildResults,
      autoRun,
    );
  }
}
