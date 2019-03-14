// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/service.dart';
import 'package:uuid/uuid.dart';

import '../serve/chrome.dart';
import '../serve/debugger/webdev_vm_client.dart';
import '../serve/handlers/dev_handler.dart';
import '../serve/server_manager.dart';
import 'daemon.dart';
import 'domain.dart';
import 'utilites.dart';

/// A collection of method and events relevant to the running application.
class AppDomain extends Domain {
  final String _appId;

  DevHandler _devHandler;
  WebdevVmClient _webdevVmClient;
  DebugService _debugService;
  bool _isShutdown = false;

  void _initialize() async {
    sendEvent('app.start', {
      'appId': _appId,
      'directory': Directory.current.path,
      'deviceId': 'chrome',
      'launchMode': 'run'
    });

    await _devHandler.connections.next;
    // TODO(https://github.com/dart-lang/webdev/issues/202) - Remove.
    await Future.delayed(Duration(seconds: 2));

    var chrome = await Chrome.connectedInstance;
    // TODO(https://github.com/dart-lang/webdev/issues/202) - Run an eval to
    // get the appId.
    var appUrl = (await chrome.chromeConnection.getTabs())
        .firstWhere((tab) => tab.url.startsWith('http://localhost'))
        .url;

    sendEvent('daemon.logMessage',
        {'level': 'info', 'message': 'Connecting to $appUrl'});

    _debugService =
        await _devHandler.startDebugService(chrome.chromeConnection, appUrl);
    _webdevVmClient = await WebdevVmClient.create(_debugService);

    sendEvent('app.debugPort', {
      'appId': _appId,
      'port': _debugService.port,
      'wsUri': _debugService.wsUri,
    });

    // Shutdown could have been triggered while awaiting above.
    // ignore: invariant_booleans
    if (_isShutdown) dispose();

    // TODO(grouma) - Add an event for when the application is started.
  }

  AppDomain(Daemon daemon, ServerManager serverManager)
      : _appId = Uuid().v1() as String,
        super(daemon, 'app') {
    registerHandler('restart', _restart);
    registerHandler('callServiceExtension', _callServiceExtension);
    registerHandler('stop', _stop);

    // TODO(https://github.com/dart-lang/webdev/issues/202) - Embed the appID
    // in the WebServer.
    var server = serverManager.servers.firstWhere((s) => s.target == 'web');
    _devHandler = server.devHandler;

    _initialize();
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
    _devHandler?.connections?.cancel();
    _debugService?.close();
    _webdevVmClient?.close();
  }
}
