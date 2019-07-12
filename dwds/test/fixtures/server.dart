// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:dwds/dwds.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

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
    ReloadConfiguration reload,
    bool startDevTools,
    Stream<BuildResults> buildResults,
  ) async {
    var pipeline = const Pipeline();

    var filteredBuildResults = buildResults.asyncMap<BuildResult>((results) =>
        results.results.firstWhere((result) => result.target == target));

    var dwds = await Dwds.start(
      hostname: hostname,
      applicationPort: port,
      applicationTarget: target,
      assetServerPort: assetServerPort,
      buildResults: filteredBuildResults,
      chromeConnection: () async => null,
      logWriter: (level, message) => print(message),
      reloadConfiguration: reload,
      serveDevTools: startDevTools,
      verbose: true,
    );

    var server = await HttpMultiServer.bind(hostname, port);
    shelf_io.serveRequests(server, pipeline.addHandler(dwds.handler));
    return TestServer._(
      target,
      server,
      dwds,
      filteredBuildResults,
      true,
    );
  }
}
