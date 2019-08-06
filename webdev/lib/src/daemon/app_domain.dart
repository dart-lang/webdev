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

import '../serve/server_manager.dart';
import 'daemon.dart';
import 'domain.dart';
import 'utilites.dart';

/// A collection of method and events relevant to the running application.
class AppDomain extends Domain {
  String _appId;

  VmService get _vmService => _debugConnection?.vmService;

  DebugConnection _debugConnection;

  StreamSubscription<BuildResult> _resultSub;
  StreamSubscription<Event> _stdOutSub;
  bool _isShutdown = false;
  int _buildProgressEventId;
  var _progressEventId = 0;

  void _handleBuildResult(BuildResult result) {
    switch (result.status) {
      case BuildStatus.started:
        _buildProgressEventId = _progressEventId++;
        sendEvent('app.progress', {
          'appId': _appId,
          'id': '$_buildProgressEventId',
          'message': 'Building...',
        });
        break;
      case BuildStatus.failed:
        sendEvent('app.progress', {
          'appId': _appId,
          'id': '$_buildProgressEventId',
          'finished': true,
        });
        break;
      case BuildStatus.succeeded:
        sendEvent('app.progress', {
          'appId': _appId,
          'id': '$_buildProgressEventId',
          'finished': true,
        });
        break;
    }
  }

  void _initialize(ServerManager serverManager) async {
    var server = serverManager.servers.first;
    var dwds = server.dwds;
    // The connection is established right before `main()` is called.
    await for (var appConnection in dwds.connectedApps) {
      await _stdOutSub?.cancel();
      await _resultSub?.cancel();
      _debugConnection = await dwds.debugConnection(appConnection);
      _appId = appConnection.request.appId;
      unawaited(_debugConnection.onDone.then((_) {
        sendEvent('app.log', {
          'appId': _appId,
          'log': 'Lost connection to device.',
        });
        sendEvent('app.stop', {
          'appId': _appId,
        });
        daemon.shutdown();
      }));
      sendEvent('app.start', {
        'appId': _appId,
        'directory': Directory.current.path,
        'deviceId': 'chrome',
        'launchMode': 'run'
      });
      sendEvent('app.started', {
        'appId': _appId,
      });
      // TODO(grouma) - limit the catch to the appropriate error.
      try {
        await _vmService.streamCancel('Stdout');
      } catch (_) {}
      try {
        await _vmService.streamListen('Stdout');
      } catch (_) {}
      _stdOutSub = _vmService.onStdoutEvent.listen((log) {
        sendEvent('app.log', {
          'appId': _appId,
          'log': utf8.decode(base64.decode(log.bytes)),
        });
      });
      sendEvent('app.debugPort', {
        'appId': _appId,
        'port': _debugConnection.port,
        'wsUri': _debugConnection.uri,
      });
      _resultSub = server.buildResults.listen(_handleBuildResult);

      appConnection.runMain();
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
    if (_appId != appId) throw ArgumentError.value(appId, 'appId', 'Not found');
    var methodName = getStringArg(args, 'methodName', required: true);
    var params = args['params'] != null
        ? (args['params'] as Map<String, dynamic>)
        : <String, dynamic>{};
    var response =
        await _vmService.callServiceExtension(methodName, args: params);
    return response.json;
  }

  Future<Map<String, dynamic>> _restart(Map<String, dynamic> args) async {
    var appId = getStringArg(args, 'appId', required: true);
    if (_appId != appId) throw ArgumentError.value(appId, 'appId', 'Not found');
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
      'appId': _appId,
      'id': '$_progressEventId',
      'message': 'Performing hot restart...',
      'progressId': 'hot.restart',
    });
    var response = await _vmService.callServiceExtension('hotRestart');
    sendEvent('app.progress', {
      'appId': _appId,
      'id': '$_progressEventId',
      'finished': true,
      'progressId': 'hot.restart',
    });
    sendEvent('app.log', {
      'appId': _appId,
      'log': 'Restarted application in ${stopwatch.elapsedMilliseconds}ms'
    });
    return {
      'code': response.type == 'Success' ? 0 : 1,
      'message': response.toString()
    };
  }

  Future<bool> _stop(Map<String, dynamic> args) async {
    var appId = getStringArg(args, 'appId', required: true);
    if (_appId != appId) throw ArgumentError.value(appId, 'appId', 'Not found');
    // Note that this triggers the daemon to shutdown as we listen for the
    // tabConnection to close to initiate a shutdown.
    await _debugConnection?.close();
    // Wait for the daemon to gracefully shutdown before sending success.
    await daemon.onExit;
    return true;
  }

  @override
  void dispose() {
    _isShutdown = true;
    _stdOutSub?.cancel();
    _resultSub?.cancel();
    _debugConnection?.close();
  }
}
