import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:webdriver/io.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

class TestContext {
  String appUrl;
  DebugService debugService;
  ChromeProxyService get chromeProxyService =>
      debugService.chromeProxyService as ChromeProxyService;
  WipConnection tabConnection;
  Process webdev;
  WebDriver webDriver;
  Process chromeDriver;
  int port;

  /// The directory in which we run pub serve.
  String directory;

  /// The path to pass to webdev serve.
  String pathToServe;

  /// The path part of the application URL.
  String path;

  TestContext(
      {String directory,
      this.path = 'hello_world/index.html',
      this.pathToServe = 'example'}) {
    this.directory = directory ?? p.relative('../_test', from: p.current);
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

    await Process.run('pub', ['get'], workingDirectory: directory);

    webdev = await Process.start(
        'pub', ['run', 'webdev', 'serve', '$pathToServe:$port'],
        workingDirectory: directory);
    webdev.stderr
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen(print);
    var assetReadyCompleter = Completer();
    webdev.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen((line) {
      if (line.contains('$port') && !assetReadyCompleter.isCompleted) {
        assetReadyCompleter.complete();
      }
      printOnFailure(line);
    });
    await assetReadyCompleter.future.timeout(Duration(seconds: 60));
    appUrl = 'http://localhost:$port/$path';
    var debugPort = await findUnusedPort();
    var capabilities = Capabilities.chrome
      ..addAll({
        Capabilities.chromeOptions: {
          'args': ['remote-debugging-port=$debugPort', '--headless']
        }
      });
    webDriver =
        await createDriver(spec: WebDriverSpec.JsonWire, desired: capabilities);
    await webDriver.get(appUrl);
    var connection = ChromeConnection('localhost', debugPort);
    var tab = await connection.getTab((t) => t.url == appUrl);
    tabConnection = await tab.connect();
    await tabConnection.runtime.enable();
    await tabConnection.debugger.enable();

    // Check if the app is already loaded, look for the top level
    // `registerExtension` variable which we set as the last step.
    var result = await tabConnection.runtime
        .evaluate('(window.registerExtension !== undefined).toString();');
    if (result.value != 'true') {
      // If it wasn't already loaded, then wait for the 'Page Ready' log.
      await tabConnection.runtime.onConsoleAPICalled.firstWhere((event) =>
          event.type == 'debug' && event.args[0].value == 'Page Ready');
    }

    var assetHandler = (String path) async {
      var result = await http.get('http://localhost:$port/$path');
      return result.body;
    };

    var instanceId =
        await tabConnection.runtime.evaluate(r'window.$dartAppInstanceId');

    debugService = await DebugService.start(
        'localhost', connection, assetHandler, instanceId.value.toString());
  }

  Future<Null> tearDown() async {
    webdev.kill();
    await webdev.exitCode;
    await webDriver?.quit();
    chromeDriver.kill();
  }
}
