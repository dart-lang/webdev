// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:dwds/dwds.dart';
import 'package:pedantic/pedantic.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webdev/src/serve/webdev_server.dart';

import '../serve/server_manager.dart';
import 'daemon.dart';
import 'domain.dart';
import 'utilites.dart';

/// A collection of method and events relevant to the running application.
class AppDomain extends Domain {
  bool _isShutdown = false;
  int _buildProgressEventId;
  var _progressEventId = 0;

  final _appStates = <String, _AppState>{};

  void _handleBuildResult(BuildResult result, String appId) {
    switch (result.status) {
      case BuildStatus.started:
        _buildProgressEventId = _progressEventId++;
        sendEvent('app.progress', {
          'appId': appId,
          'id': '$_buildProgressEventId',
          'message': 'Building...',
        });
        break;
      case BuildStatus.failed:
        sendEvent('app.progress', {
          'appId': appId,
          'id': '$_buildProgressEventId',
          'finished': true,
        });
        break;
      case BuildStatus.succeeded:
        sendEvent('app.progress', {
          'appId': appId,
          'id': '$_buildProgressEventId',
          'finished': true,
        });
        break;
    }
  }

  void _initialize(ServerManager serverManager) {
    serverManager.servers.forEach(_handleAppConnections);
  }

  void _handleAppConnections(WebDevServer server) async {
    var dwds = server.dwds;
    // The connection is established right before `main()` is called.
    await for (var appConnection in dwds.connectedApps) {
      var debugConnection = await dwds.debugConnection(appConnection);
      var vmService = debugConnection.vmService;
      var appId = appConnection.request.appId;
      unawaited(debugConnection.onDone.then((_) {
        sendEvent('app.log', {
          'appId': appId,
          'log': 'Lost connection to device.',
        });
        sendEvent('app.stop', {
          'appId': appId,
        });
        daemon.shutdown();
      }));
      sendEvent('app.start', {
        'appId': appId,
        'directory': Directory.current.path,
        'deviceId': 'chrome',
        'launchMode': 'run'
      });
      sendEvent('app.started', {
        'appId': appId,
      });
      // TODO(grouma) - limit the catch to the appropriate error.
      try {
        await vmService.streamCancel('Stdout');
      } catch (_) {}
      try {
        await vmService.streamListen('Stdout');
      } catch (_) {}
      // ignore: cancel_subscriptions
      var stdOutSub = vmService.onStdoutEvent.listen((log) {
        sendEvent('app.log', {
          'appId': appId,
          'log': utf8.decode(base64.decode(log.bytes)),
        });
      });
      sendEvent('app.debugPort', {
        'appId': appId,
        'port': debugConnection.port,
        'wsUri': debugConnection.uri,
      });
      // ignore: cancel_subscriptions
      var resultSub =
          server.buildResults.listen((r) => _handleBuildResult(r, appId));

      var appState = _AppState(debugConnection, resultSub, stdOutSub);
      _appStates[appId] = appState;

      appConnection.runMain();

      unawaited(debugConnection.onDone.whenComplete(() {
        appState.dispose();
        _appStates.remove(appId);
      }));
    }

    // Shutdown could have been triggered while awaiting above.
    if (_isShutdown) dispose();
  }

  AppDomain(Daemon daemon, ServerManager serverManager) : super(daemon, 'app') {
    registerHandler('restart', _restart);
    registerHandler('callServiceExtension', _callServiceExtension);
    registerHandler('stop', _stop);

    _initialize(serverManager);
  }

  Future<Map<String, dynamic>> _callServiceExtension(
      Map<String, dynamic> args) async {
    var appId = getStringArg(args, 'appId', required: true);
    var appState = _appStates[appId];
    if (appState == null) {
      throw ArgumentError.value(appId, 'appId', 'Not found');
    }
    var methodName = getStringArg(args, 'methodName', required: true);
    var params = args['params'] != null
        ? (args['params'] as Map<String, dynamic>)
        : <String, dynamic>{};
    var response =
        await appState.vmService.callServiceExtension(methodName, args: params);
    return response.json;
  }

  Future<Map<String, dynamic>> _restart(Map<String, dynamic> args) async {
    var appId = getStringArg(args, 'appId', required: true);
    var appState = _appStates[appId];
    if (appState == null) {
      throw ArgumentError.value(appId, 'appId', 'Not found');
    }
    var fullRestart = getBoolArg(args, 'fullRestart') ?? false;
    if (!fullRestart) {
      return {
        'code': 1,
        'message': 'hot reload not yet supported by package:flutter_web',
      };
    }
    // TODO(grouma) - Support pauseAfterRestart.
    // var pauseAfterRestart = getBoolArg(args, 'pause') ?? false;
    var stopwatch = Stopwatch()..start();
    _progressEventId++;
    sendEvent('app.progress', {
      'appId': appId,
      'id': '$_progressEventId',
      'message': 'Performing hot restart...',
      'progressId': 'hot.restart',
    });
    var response = await appState.vmService.callServiceExtension('hotRestart');
    sendEvent('app.progress', {
      'appId': appId,
      'id': '$_progressEventId',
      'finished': true,
      'progressId': 'hot.restart',
    });
    sendEvent('app.log', {
      'appId': appId,
      'log': 'Restarted application in ${stopwatch.elapsedMilliseconds}ms'
    });
    return {
      'code': response.type == 'Success' ? 0 : 1,
      'message': response.toString()
    };
  }

  Future<bool> _stop(Map<String, dynamic> args) async {
    var appId = getStringArg(args, 'appId', required: true);
    var appState = _appStates[appId];
    if (appState == null) {
      throw ArgumentError.value(appId, 'appId', 'Not found');
    }
    // Note that this triggers the daemon to shutdown as we listen for the
    // tabConnection to close to initiate a shutdown.
    await appState._debugConnection?.close();
    // Wait for the daemon to gracefully shutdown before sending success.
    await daemon.onExit;
    return true;
  }

  @override
  void dispose() {
    _isShutdown = true;
    for (var state in _appStates.values) {
      state.dispose();
    }
    _appStates.clear();
  }
}

class _AppState {
  final DebugConnection _debugConnection;
  final StreamSubscription<BuildResult> _resultSub;
  final StreamSubscription<Event> _stdOutSub;

  bool _isDisposed = false;

  VmService get vmService => _debugConnection?.vmService;

  _AppState(this._debugConnection, this._resultSub, this._stdOutSub);

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _stdOutSub?.cancel();
    _resultSub?.cancel();
    _debugConnection?.close();
  }
}
