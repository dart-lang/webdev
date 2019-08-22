// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:webdriver/io.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'server.dart';
import 'utilities.dart';

class TestContext {
  String appUrl;
  WipConnection tabConnection;
  WipConnection extensionConnection;
  TestServer testServer;
  BuildDaemonClient daemonClient;
  WebDriver webDriver;
  Process chromeDriver;
  AppConnection appConnection;
  DebugConnection debugConnection;
  WebkitDebugger webkitDebugger;
  int port;
  File _entryFile;
  String _entryContents;

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
    _entryFile = File(p.absolute(p.join(p.relative('../_test', from: p.current),
        'example', 'append_body', 'main.dart')));
    _entryContents = _entryFile.readAsStringSync();
  }

  Future<void> setUp(
      {ReloadConfiguration reloadConfiguration,
      bool serveDevTools,
      bool enableDebugExtension}) async {
    reloadConfiguration ??= ReloadConfiguration.none;
    serveDevTools ??= false;
    enableDebugExtension ??= false;
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
        .timeout(const Duration(seconds: 60));

    var debugPort = await findUnusedPort();
    // If the environment variable DWDS_DEBUG_CHROME is set to the string true
    // then Chrome will be launched with a UI rather than headless.
    // If the extension is enabled, then Chrome will be launched with a UI
    // since headless Chrome does not support extensions.
    var headless = Platform.environment['DWDS_DEBUG_CHROME'] != 'true' &&
        !enableDebugExtension;
    var capabilities = Capabilities.chrome
      ..addAll({
        Capabilities.chromeOptions: {
          'args': [
            'remote-debugging-port=$debugPort',
            if (enableDebugExtension) '--load-extension=debug_extension/web',
            if (headless) '--headless'
          ]
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
      reloadConfiguration,
      serveDevTools,
      enableDebugExtension,
    );

    appUrl = 'http://localhost:$port/$path';
    await webDriver.get(appUrl);
    var tab = await connection.getTab((t) => t.url == appUrl);
    tabConnection = await tab.connect();
    await tabConnection.runtime.enable();
    await tabConnection.debugger.enable();

    if (enableDebugExtension) {
      var extensionTab = await fetchExtensionTab(connection);
      extensionConnection = await extensionTab.connect();
      await extensionConnection.runtime.enable();
    }

    appConnection = await testServer.dwds.connectedApps.first;
    debugConnection = await testServer.dwds.debugConnection(appConnection);
    webkitDebugger = WebkitDebugger(WipDebugger(tabConnection));
  }

  Future<Null> tearDown() async {
    _entryFile.writeAsStringSync(_entryContents);
    await daemonClient.close();
    await testServer.stop();
    await webDriver?.quit();
    chromeDriver.kill();
  }

  Future<void> changeInput() async {
    _entryFile.writeAsStringSync(
        _entryContents.replaceAll('Hello World!', 'Gary is awesome!'));

    // Wait for the build.
    await daemonClient.buildResults.firstWhere((results) => results.results
        .any((result) => result.status == BuildStatus.succeeded));

    // Allow change to propagate to the browser.
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<ChromeTab> fetchExtensionTab(ChromeConnection connection) async {
    for (var tab in await connection.getTabs()) {
      var tabConnection = await tab.connect();
      var response =
          await tabConnection.runtime.evaluate('window.isDartDebugExtension');
      if (response.value == true) {
        return tab;
      }
    }
    throw StateError('No extension installed.');
  }
}
