// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build_daemon/data/build_status.dart';
import 'package:shelf/shelf.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webdev/src/serve/handlers/dev_handler.dart';

import 'command/configuration.dart';
import 'serve/chrome.dart';
import 'serve/debugger/app_debug_services.dart';
import 'serve/debugger/devtools.dart';
import 'serve/injected/configuration.dart';
import 'serve/webdev_server.dart';

Future<WebDevHandle> connectToWebdev(
  int port,
  int assetPort,
  String target,
  Stream<BuildResults> buildResults, {
  Handler optionalHandler,
  Uri devtoolsUri,
}) async {
  var hostname = 'localhost';
  var configuration = Configuration(
    hostname: hostname,
    requireBuildWebCompilers: false,
    debug: true,
    autoRun: true,
    reload: ReloadConfiguration.none,
  );
  var devtools = await DevTools.start(hostname, overrideUri: devtoolsUri);
  var serverOptions = ServerOptions(
    configuration,
    port,
    target,
    assetPort,
    optionalHandler: optionalHandler,
  );
  var webDevServer =
      await WebDevServer.start(serverOptions, buildResults, devtools);
  var chrome = await Chrome.start(
      <String>['http://${webDevServer.host}:${webDevServer.port}/'],
      port: configuration.chromeDebugPort);
  var devHandler = webDevServer.devHandler;
  var connection = await devHandler.connectedApps.first;
  var appDebugServices = await devHandler.loadAppServices(
      connection.request.appId, connection.request.instanceId);
  return WebDevHandle(
      appDebugServices, connection, chrome, webDevServer, devtools);
}

class WebDevHandle {
  final AppDebugServices _appDebugServices;
  final DevConnection _devConnection;
  final Chrome _chrome;
  final WebDevServer _webDevServer;
  final DevTools _devTools;

  WebDevHandle(this._appDebugServices, this._devConnection, this._chrome,
      this._webDevServer, this._devTools);

  Future<void> close() async {
    await _webDevServer.stop();
    await _chrome.close();
    await _devTools.close();
    await _appDebugServices.close();
  }

  VmService get vmService {
    return _appDebugServices.webdevClient.client;
  }

  Stream<void> get onTabClose {
    return _appDebugServices.chromeProxyService.tabConnection.onClose;
  }

  Uri get wsUri => Uri.parse(_appDebugServices.debugService.wsUri);

  void runMain() => _devConnection.runMain();
}
