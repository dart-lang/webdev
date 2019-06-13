// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build_daemon/data/build_status.dart';
import 'package:shelf/shelf.dart';
import 'package:webdev/src/serve/handlers/dev_handler.dart';

import 'src/command/configuration.dart';
import 'src/serve/chrome.dart';
import 'src/serve/debugger/app_debug_services.dart';
import 'src/serve/debugger/devtools.dart';
import 'src/serve/webdev_server.dart';

export 'src/command/configuration.dart' show Configuration, ReloadConfiguration;
export 'src/daemon_client.dart' show daemonPort;
export 'src/serve/debugger/app_debug_services.dart' show AppDebugServices;
export 'src/serve/debugger/devtools.dart' show DevTools;

Future<WebDevHandler> connectToWebdev(
  Configuration configuration,
  int port,
  int assetPort,
  String target,
  Stream<BuildResults> buildResults,
  DevTools devTools, {
  Handler optionalHandler,
}) async {
  var serverOptions = ServerOptions(
    configuration,
    port,
    target,
    assetPort,
    optionalHandler,
  );
  var webDevServer =
      await WebDevServer.start(serverOptions, buildResults, devTools);
  var chrome = await Chrome.start(
      <String>['http://${webDevServer.host}:${webDevServer.port}/'],
      port: configuration.chromeDebugPort);
  var devHandler = webDevServer.devHandler;
  var connection = await devHandler.connectedApps.first;
  var appDebugServices = await devHandler.loadAppServices(
      connection.request.appId, connection.request.instanceId);
  return WebDevHandler(appDebugServices, connection, chrome, webDevServer);
}

class WebDevHandler {
  final AppDebugServices appDebugServices;
  final DevConnection devConnection;
  final Chrome _chrome;
  final WebDevServer _webDevServer;

  WebDevHandler(this.appDebugServices, this.devConnection, this._chrome, this._webDevServer);

  Future<void> close() async {
    await _webDevServer.stop();
    await _chrome.close();
    await appDebugServices.close();
  }
}
