// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/service.dart';

import '../serve/chrome.dart';
import '../serve/debugger/webdev_vm_client.dart';
import '../serve/server_manager.dart';
import 'daemon.dart';
import 'domain.dart';
import 'utilites.dart';

/// A collection of method and events relevant to the running application.
class AppDomain extends Domain {
  String _appId;
  WebdevVmClient _webdevVmClient;
  DebugService _debugService;
  bool _isShutdown = false;

  void _initialize(ServerManager serverManager) async {
    var devHandler = serverManager.servers.first.devHandler;
    // The connection is established right before `main()` is called.
    _appId = await devHandler.connectedApps.first;
    sendEvent('app.start', {
      'appId': _appId,
      'directory': Directory.current.path,
      'deviceId': 'chrome',
      'launchMode': 'run'
    });
    var chrome = await Chrome.connectedInstance;
    _debugService =
        await devHandler.startDebugService(chrome.chromeConnection, _appId);
    _webdevVmClient = await WebdevVmClient.create(_debugService);
    sendEvent('app.debugPort', {
      'appId': _appId,
      'port': _debugService.port,
      'wsUri': _debugService.wsUri,
    });
    sendEvent('app.started', {
      'appId': _appId,
    });
    // Shutdown could have been triggered while awaiting above.
    if (_isShutdown) dispose();
  }

  AppDomain(Daemon daemon, ServerManager serverManager) : super(daemon, 'app') {
    registerHandler('restart', _restart);
    registerHandler('callServiceExtension', _callServiceExtension);
    registerHandler('stop', _stop);

    _initialize(serverManager);
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
    _isShutdown = true;
    _debugService?.close();
    _webdevVmClient?.close();
  }
}
