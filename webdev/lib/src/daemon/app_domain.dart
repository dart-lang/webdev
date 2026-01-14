// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/data/build_result.dart';
import 'package:dwds/dwds.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../serve/server_manager.dart';
import '../serve/webdev_server.dart';
import 'daemon.dart';
import 'domain.dart';
import 'utilites.dart';

/// A collection of method and events relevant to the running application.
class AppDomain extends Domain {
  bool _isShutdown = false;
  int? _buildProgressEventId;
  var _progressEventId = 0;

  final _appStates = <String, _AppState>{};

  // Mapping from service name to service method.
  final Map<String, String> _registeredMethodsForService = <String, String>{};

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

  Future<void> _handleAppConnections(WebDevServer server) async {
    final dwds = server.dwds!;

    // The connection is established right before `main()` is called.
    await for (final appConnection in dwds.connectedApps) {
      final appId = appConnection.request.appId;

      // Check if we already have an active app state for this appId
      if (_appStates.containsKey(appId)) {
        // Reuse existing connection, just run main again
        appConnection.runMain();
        continue;
      }

      final debugConnection = await dwds.debugConnection(appConnection);
      final debugUri = debugConnection.ddsUri ?? debugConnection.uri;
      final vmService = await vmServiceConnectUri(debugUri);

      sendEvent('app.start', {
        'appId': appId,
        'directory': Directory.current.path,
        'deviceId': 'chrome',
        'launchMode': 'run',
      });

      // Set up VM service listeners for this appId
      // ignore: cancel_subscriptions
      final stdOutSub = await _setupVmServiceListeners(appId, vmService);

      sendEvent('app.debugPort', {
        'appId': appId,
        'port': debugConnection.port,
        'wsUri': debugConnection.uri,
      });
      // ignore: cancel_subscriptions
      final resultSub = server.buildResults.listen(
        (r) => _handleBuildResult(r, appId),
      );

      final appState = _AppState(debugConnection, resultSub, stdOutSub);
      _appStates[appId] = appState;
      sendEvent('app.started', {'appId': appId});

      appConnection.runMain();

      // Handle connection termination - send events first, then cleanup
      unawaited(
        debugConnection.onDone.whenComplete(() {
          sendEvent('app.log', {
            'appId': appId,
            'log': 'Lost connection to device.',
          });
          sendEvent('app.stop', {'appId': appId});
          daemon.shutdown();

          // Clean up app resources
          _cleanupAppConnection(appId, appState);
        }),
      );
    }

    // Shutdown could have been triggered while awaiting above.
    if (_isShutdown) dispose();
  }

  void _onServiceEvent(Event e) {
    if (e.kind == EventKind.kServiceRegistered) {
      final serviceName = e.service!;
      _registeredMethodsForService[serviceName] = e.method!;
    }

    if (e.kind == EventKind.kServiceUnregistered) {
      final serviceName = e.service!;
      _registeredMethodsForService.remove(serviceName);
    }
  }

  AppDomain(Daemon daemon, ServerManager serverManager) : super(daemon, 'app') {
    registerHandler('restart', _restart);
    registerHandler('callServiceExtension', _callServiceExtension);
    registerHandler('stop', _stop);

    _initialize(serverManager);
  }

  Future<Map<String, dynamic>?> _callServiceExtension(
    Map<String, dynamic> args,
  ) async {
    final appId = getStringArg(args, 'appId', required: true);
    final appState = _appStates[appId];
    if (appState == null) {
      throw ArgumentError.value(appId, 'appId', 'Not found');
    }
    final methodName = getStringArg(args, 'methodName', required: true)!;
    final params = args['params'] != null
        ? (args['params'] as Map<String, dynamic>)
        : <String, dynamic>{};
    final response = await appState.vmService!.callServiceExtension(
      methodName,
      args: params,
    );
    return response.json;
  }

  Future<Map<String, dynamic>> _restart(Map<String, dynamic> args) async {
    final appId = getStringArg(args, 'appId', required: true);
    final appState = _appStates[appId];
    if (appState == null) {
      throw ArgumentError.value(appId, 'appId', 'Not found');
    }
    final fullRestart = getBoolArg(args, 'fullRestart') ?? false;
    if (!fullRestart) {
      return {'code': 1, 'message': 'hot reload not yet supported by webdev'};
    }
    // TODO(grouma) - Support pauseAfterRestart.
    // var pauseAfterRestart = getBoolArg(args, 'pause') ?? false;
    final stopwatch = Stopwatch()..start();
    _progressEventId++;
    sendEvent('app.progress', {
      'appId': appId,
      'id': '$_progressEventId',
      'message': 'Performing hot restart...',
      'progressId': 'hot.restart',
    });
    final restartMethod =
        _registeredMethodsForService['hotRestart'] ?? 'hotRestart';
    final response = await appState.vmService!.callServiceExtension(
      restartMethod,
    );
    sendEvent('app.progress', {
      'appId': appId,
      'id': '$_progressEventId',
      'finished': true,
      'progressId': 'hot.restart',
    });
    sendEvent('app.log', {
      'appId': appId,
      'log': 'Restarted application in ${stopwatch.elapsedMilliseconds}ms',
    });
    return {
      'code': response.type == 'Success' ? 0 : 1,
      'message': response.toString(),
    };
  }

  Future<bool> _stop(Map<String, dynamic> args) async {
    final appId = getStringArg(args, 'appId', required: true);
    final appState = _appStates[appId];
    if (appState == null) {
      throw ArgumentError.value(appId, 'appId', 'Not found');
    }
    // Note that this triggers the daemon to shutdown as we listen for the
    // tabConnection to close to initiate a shutdown.
    await appState._debugConnection.close();
    // Wait for the daemon to gracefully shutdown before sending success.
    await daemon.onExit;
    return true;
  }

  /// Sets up VM service listeners for the given appId.
  /// Returns the stdout subscription.
  Future<StreamSubscription<Event>> _setupVmServiceListeners(
    String appId,
    VmService vmService,
  ) async {
    try {
      vmService.onServiceEvent.listen(_onServiceEvent);
      await vmService.streamListen(EventStreams.kService);
    } catch (_) {}

    // ignore: cancel_subscriptions
    final stdoutSubscription = vmService.onStdoutEvent.listen((log) {
      sendEvent('app.log', {
        'appId': appId,
        'log': utf8.decode(base64.decode(log.bytes!)),
      });
    });

    try {
      await vmService.streamListen(EventStreams.kStdout);
    } catch (_) {}

    return stdoutSubscription;
  }

  /// Cleans up an app connection and its associated listeners.
  void _cleanupAppConnection(String appId, _AppState appState) {
    appState.dispose();
    _appStates.remove(appId);
  }

  @override
  void dispose() {
    _isShutdown = true;
    for (final state in _appStates.values) {
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

  VmService? get vmService => _debugConnection.vmService;

  _AppState(this._debugConnection, this._resultSub, this._stdOutSub);

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _stdOutSub.cancel();
    _resultSub.cancel();
    _debugConnection.close();
  }
}
