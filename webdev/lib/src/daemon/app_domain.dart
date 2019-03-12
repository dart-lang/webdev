// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../serve/controller.dart';
import 'daemon.dart';
import 'domain.dart';
import 'utilites.dart';

/// A collection of method and events relevant to the running application.
class AppDomain extends Domain {
  final String _appId;

  Future<ServeController> _serveController;

  AppDomain(Daemon daemon, this._serveController)
      : _appId = Uuid().v1() as String,
        super(daemon, 'app') {
    registerHandler('restart', _restart);
    registerHandler('callServiceExtension', _callServiceExtension);
    registerHandler('stop', _stop);

    _serveController.then((controller) async {
      sendEvent('app.start', {
        'appId': _appId,
        'directory': Directory.current.path,
        'deviceId': 'chrome',
        'launchMode': 'run'
      });

      // TODO(https://github.com/dart-lang/webdev/issues/202) - Embed the appID
      // in the WebServer.
      var server =
          controller.serverManager.servers.firstWhere((s) => s.target == 'web');
      var devHandler = server.devHandler;
      await devHandler.connections.next;
      // TODO(https://github.com/dart-lang/webdev/issues/202) - Remove.
      await Future.delayed(Duration(seconds: 1));

      var chrome = controller.chrome;
      // TODO(https://github.com/dart-lang/webdev/issues/202) - Run an eval to
      // get the appId.
      var appUrl = (await chrome.chromeConnection.getTabs())
          .firstWhere((tab) => tab.url.startsWith('http://localhost'))
          .url;

      var client =
          await server.devHandler.createClient(chrome, 'localhost', appUrl);

      sendEvent('app.debugPort', {
        'appId': _appId,
        'port': client.port,
        'wsUri': client.wsUri,
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
    var serve = await _serveController;
    await serve.shutDown();
    return true;
  }
}
