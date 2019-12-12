// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webdriver/io.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'server.dart';
import 'utilities.dart';

final _batExt = Platform.isWindows ? '.bat' : '';
final _exeExt = Platform.isWindows ? '.exe' : '';

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
    workingDirectory = p.normalize(p.absolute(
        directory ?? p.relative('../fixtures/_test', from: p.current)));
    DartUri.currentDirectory = workingDirectory;
    _entryFile = File(p.absolute(p.join(
        p.relative('../fixtures/_test', from: p.current),
        'example',
        'append_body',
        'main.dart')));
    _entryContents = _entryFile.readAsStringSync();
  }

  Future<void> setUp(
      {ReloadConfiguration reloadConfiguration,
      bool serveDevTools,
      bool enableDebugExtension,
      bool autoRun,
      bool enableDebugging,
      bool waitToDebug,
      UrlEncoder urlEncoder,
      bool restoreBreakpoints}) async {
    reloadConfiguration ??= ReloadConfiguration.none;
    serveDevTools ??= false;
    enableDebugExtension ??= false;
    autoRun ??= true;
    enableDebugging ??= true;
    waitToDebug ??= false;
    var chromeDriverPort = await findUnusedPort();
    var chromeDriverUrlBase = 'wd/hub';
    try {
      print('PRINTING WHERE');
      print(Process.runSync('where$_exeExt', ['chromedriver.exe']).stdout);
      print('PRINTING VERSION WITHOUT PARENT');
      print(Process.runSync('chromedriver$_exeExt', ['--version']).stdout);
      chromeDriver = await Process.start('chromedriver$_exeExt',
          ['--port=$chromeDriverPort', '--url-base=$chromeDriverUrlBase']);
      // On windows this takes a while to boot up, wait for the first line
      // of stdout as a signal that it is ready.
      await chromeDriver.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
    } catch (e) {
      throw StateError(
          'Could not start ChromeDriver. Is it installed?\nError: $e');
    }

    await Process.run('pub$_batExt', ['upgrade'],
        workingDirectory: workingDirectory);

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
    webDriver = await createDriver(
        spec: WebDriverSpec.JsonWire,
        desired: capabilities,
        uri: Uri.parse(
            'http://127.0.0.1:$chromeDriverPort/$chromeDriverUrlBase/'));
    var connection = ChromeConnection('localhost', debugPort);

    port = await findUnusedPort();
    testServer = await TestServer.start(
        port,
        daemonPort(workingDirectory),
        pathToServe,
        daemonClient.buildResults,
        () async => connection,
        reloadConfiguration,
        serveDevTools,
        enableDebugExtension,
        autoRun,
        enableDebugging,
        urlEncoder,
        restoreBreakpoints);

    appUrl = 'http://localhost:$port/$path';
    await webDriver.get(appUrl);
    var tab = await connection.getTab((t) => t.url == appUrl);
    tabConnection = await tab.connect();
    await tabConnection.runtime.enable();
    await tabConnection.debugger.enable();

    if (enableDebugExtension) {
      var extensionTab = await _fetchDartDebugExtensionTab(connection);
      extensionConnection = await extensionTab.connect();
      await extensionConnection.runtime.enable();
    }

    appConnection = await testServer.dwds.connectedApps.first;
    if (enableDebugging && !waitToDebug) {
      await startDebugging();
    }
  }

  Future<void> startDebugging() async {
    debugConnection = await testServer.dwds.debugConnection(appConnection);
    webkitDebugger = WebkitDebugger(WipDebugger(tabConnection));
  }

  Future<Null> tearDown() async {
    await webDriver?.quit(closeSession: true);
    chromeDriver?.kill();
    DartUri.currentDirectory = p.current;
    _entryFile.writeAsStringSync(_entryContents);
    await daemonClient?.close();
    await testServer?.stop();
  }

  Future<void> changeInput() async {
    _entryFile.writeAsStringSync(
        _entryContents.replaceAll('Hello World!', 'Gary is awesome!'));

    // Wait for the build.
    await daemonClient.buildResults.firstWhere((results) => results.results
        .any((result) => result.status == BuildStatus.succeeded));

    // Allow change to propagate to the browser.
    // Windows, or at least Travis on Windows, seems to need more time.
    var delay = Platform.isWindows
        ? const Duration(seconds: 5)
        : const Duration(seconds: 2);
    await Future.delayed(delay);
  }

  Future<ChromeTab> _fetchDartDebugExtensionTab(
      ChromeConnection connection) async {
    var extensionTabs = (await connection.getTabs()).where((tab) {
      return tab.isChromeExtension;
    });
    for (var tab in extensionTabs) {
      var tabConnection = await tab.connect();
      var response =
          await tabConnection.runtime.evaluate('window.isDartDebugExtension');
      if (response.value == true) {
        return tab;
      }
    }
    throw StateError('No extension installed.');
  }

  /// Finds the line number in [scriptRef] matching [breakpointId].
  ///
  /// A breakpoint ID is found by looking for a line that ends with a comment
  /// of exactly this form: `// Breakpoint: <id>`.
  ///
  /// Throws if it can't find the matching line.
  Future<int> findBreakpointLine(
      String breakpointId, String isolateId, ScriptRef scriptRef) async {
    var script = await debugConnection.vmService
        .getObject(isolateId, scriptRef.id) as Script;
    var lines = LineSplitter.split(script.source).toList();
    var lineNumber =
        lines.indexWhere((l) => l.endsWith('// Breakpoint: $breakpointId'));
    if (lineNumber == -1) {
      throw StateError('Unable to find breakpoint in ${scriptRef.uri} with id '
          '$breakpointId');
    }
    return lineNumber + 1;
  }
}
