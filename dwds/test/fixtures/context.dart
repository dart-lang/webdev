// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:webdriver/io.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'server.dart';
import 'utilities.dart';

class TestContext {
  String appUrl;
  WipConnection tabConnection;
  TestServer testServer;
  BuildDaemonClient daemonClient;
  WebDriver webDriver;
  Process chromeDriver;
  AppConnection appConnection;
  DebugConnection debugConnection;
  ChromeProxyService chromeProxyService;
  int port;

  /// Top level directory in which we run the test server..
  String workingDirectory;

  /// The path to build and serve.
  String pathToServe;

  /// The path part of the application URL.
  String path;

  TestContext(
      {String directory,
      this.path = 'hello_world/index.html',
      this.pathToServe = 'example'}) {
    workingDirectory = p.normalize(
        p.absolute(directory ?? p.relative('../_test', from: p.current)));
  }

  Future<void> setUp() async {
    port = await findUnusedPort();
    try {
      chromeDriver = await Process.start(
          'chromedriver', ['--port=4444', '--url-base=wd/hub']);
    } catch (e) {
      throw StateError(
          'Could not start ChromeDriver. Is it installed?\nError: $e');
    }

    await Process.run('pub', ['get'], workingDirectory: workingDirectory);

    daemonClient = await connectClient(
        workingDirectory, [], (log) => printOnFailure(log.toString()));
    daemonClient.registerBuildTarget(
        DefaultBuildTarget((b) => b..target = pathToServe));
    daemonClient.startBuild();

    await daemonClient.buildResults
        .firstWhere((results) => results.results
            .any((result) => result.status == BuildStatus.succeeded))
        .timeout(Duration(seconds: 60));

    var debugPort = await findUnusedPort();
    var capabilities = Capabilities.chrome
      ..addAll({
        Capabilities.chromeOptions: {
          'args': ['remote-debugging-port=$debugPort', '--headless']
        }
      });
    webDriver =
        await createDriver(spec: WebDriverSpec.JsonWire, desired: capabilities);
    var connection = ChromeConnection('localhost', debugPort);

    testServer = await TestServer.start(
      port,
      daemonPort(workingDirectory),
      pathToServe,
      daemonClient.buildResults,
      () async => connection,
    );

    appUrl = 'http://localhost:$port/$path';
    await webDriver.get(appUrl);
    var tab = await connection.getTab((t) => t.url == appUrl);
    tabConnection = await tab.connect();
    await tabConnection.runtime.enable();
    await tabConnection.debugger.enable();

    appConnection = await testServer.dwds.connectedApps.first;
    debugConnection = await testServer.dwds.debugConnection(appConnection);

    var assetHandler = (String path) async {
      var result = await http.get('http://localhost:$port/$path');
      return result.body;
    };
    chromeProxyService = await ChromeProxyService.create(
        connection, assetHandler, appConnection.request.instanceId);
  }

  Future<Null> tearDown() async {
    await daemonClient.close();
    await testServer.stop();
    await webDriver?.quit();
    chromeDriver.kill();
  }
}
