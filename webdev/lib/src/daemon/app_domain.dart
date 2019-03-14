// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/service.dart';
import 'package:uuid/uuid.dart';
import 'package:webdev/src/serve/chrome.dart';
import 'package:webdev/src/serve/server_manager.dart';

import '../serve/debugger/webdev_vm_client.dart';
import 'daemon.dart';
import 'domain.dart';
import 'utilites.dart';

/// A collection of method and events relevant to the running application.
class AppDomain extends Domain {
  final String _appId;

  WebdevVmClient _webdevVmClient;
  DebugService _debugService;

  AppDomain(Daemon daemon, Future<ServerManager> futureServerManager)
      : _appId = Uuid().v1() as String,
        super(daemon, 'app') {
    registerHandler('restart', _restart);
    registerHandler('callServiceExtension', _callServiceExtension);
    registerHandler('stop', _stop);

    futureServerManager.then((serverManager) async {
      sendEvent('app.start', {
        'appId': _appId,
        'directory': Directory.current.path,
        'deviceId': 'chrome',
        'launchMode': 'run'
      });

      // TODO(https://github.com/dart-lang/webdev/issues/202) - Embed the appID
      // in the WebServer.
      var server = serverManager.servers.firstWhere((s) => s.target == 'web');
      var devHandler = server.devHandler;
      await devHandler.connections.next;
      // TODO(https://github.com/dart-lang/webdev/issues/202) - Remove.
      await Future.delayed(Duration(seconds: 10));

      var chrome = await Chrome.connectedInstance;
      // TODO(https://github.com/dart-lang/webdev/issues/202) - Run an eval to
      // get the appId.
      var appUrl = (await chrome.chromeConnection.getTabs())
          .firstWhere((tab) => tab.url.startsWith('http://localhost'))
          .url;

      _debugService = await server.devHandler
          .startDebugService(chrome.chromeConnection, appUrl);
      _webdevVmClient = await WebdevVmClient.create(_debugService);

      sendEvent('app.debugPort', {
        'appId': _appId,
        'port': _debugService.port,
        'wsUri': _debugService.wsUri,
      });

      // TODO(grouma) - Add an event for when the application is started.
    });
  }

  Future<String> _callServiceExtension(Map<String, dynamic> args) {
    throw UnimplementedError();
  }

  Future<String> _restart(Map<String, dynamic> args) async {
    throw UnimplementedError();
  }

  Future<bool> _stop(Map<String, dynamic> args) async {
    var appId = getStringArg(args, 'appId', required: true);
    if (_appId != appId) throw ArgumentError("app '$appId' not found");
    var chrome = await Chrome.connectedInstance;
    await chrome.close();
    return true;
  }

  @override
  void dispose() {
    _debugService?.close();
    _webdevVmClient?.close();
  }
}
