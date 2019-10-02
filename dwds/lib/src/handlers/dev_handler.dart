// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/serializers.dart' as build_daemon;
import 'package:dwds/data/error_response.dart';
import 'package:dwds/data/run_request.dart';
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/servers/extension_backend.dart';
import 'package:logging/logging.dart';
import 'package:pedantic/pedantic.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../asset_handler.dart';
import '../../data/connect_request.dart';
import '../../data/devtools_request.dart';
import '../../data/isolate_events.dart';
import '../../data/serializers.dart';
import '../connections/app_connection.dart';
import '../dwds_vm_client.dart';
import '../servers/devtools.dart';
import '../services/app_debug_services.dart';
import '../services/debug_service.dart';

/// SSE handler to enable development features like hot reload and
/// opening DevTools.
class DevHandler {
  StreamSubscription _sub;
  final SseHandler _sseHandler = SseHandler(Uri.parse(r'/$sseHandler'));
  final _injectedConnections = Set<SseConnection>();
  final DevTools _devTools;
  final AssetHandler _assetHandler;
  final String _hostname;
  final _connectedApps = StreamController<AppConnection>.broadcast();
  final _servicesByAppId = <String, Future<AppDebugServices>>{};
  final Stream<BuildResult> buildResults;
  final bool _verbose;
  final void Function(Level, String) _logWriter;
  final Future<ChromeConnection> Function() _chromeConnection;
  final ExtensionBackend _extensionBackend;
  final StreamController<DebugConnection> extensionDebugConnections =
      StreamController<DebugConnection>();
  final bool _enableDebugging;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  Stream<AppConnection> get connectedApps => _connectedApps.stream;

  DevHandler(
    this._chromeConnection,
    this.buildResults,
    this._devTools,
    this._assetHandler,
    this._hostname,
    this._verbose,
    this._logWriter,
    this._extensionBackend,
    this._enableDebugging,
  ) {
    _sub = buildResults.listen(_emitBuildResults);
    _listen();
    if (_extensionBackend != null) {
      _listenForDebugExtension();
    }
  }

  Handler get handler => _sseHandler.handler;

  Future<void> close() => _closed ??= () async {
        await _sub.cancel();
        // We listen for connections to close and remove them from the connections
        // set. Therefore we shouldn't asynchronously iterate through the
        // connections.
        await Future.wait(_injectedConnections
            .map((injectedConnection) => injectedConnection.sink.close()));
        await Future.wait(_servicesByAppId.values.map((futureServices) async {
          await (await futureServices).close();
        }));
        _servicesByAppId.clear();
      }();

  void _emitBuildResults(BuildResult result) {
    if (result.status != BuildStatus.succeeded) return;
    for (var injectedConnection in _injectedConnections) {
      injectedConnection.sink
          .add(jsonEncode(build_daemon.serializers.serialize(result)));
    }
  }

  // TODO(https://github.com/dart-lang/webdev/issues/202) - Refactor so this is
  // a getter and is created immediately.
  Future<DebugService> startDebugService(
      ChromeConnection chromeConnection, String appInstanceId) async {
    ChromeTab appTab;
    WipConnection tabConnection;
    for (var tab in await chromeConnection.getTabs()) {
      if (tab.url.startsWith('chrome-extensions:')) continue;
      tabConnection = await tab.connect();
      var result = await tabConnection.runtime
          .evaluate(r'window["$dartAppInstanceId"];');
      if (result.value == appInstanceId) {
        appTab = tab;
        break;
      }
      unawaited(tabConnection.close());
    }
    if (appTab == null) {
      throw StateError('Could not connect to application with appInstanceId: '
          '$appInstanceId');
    }

    await tabConnection.runtime.enable();

    var webkitDebugger = WebkitDebugger(WipDebugger(tabConnection));

    return DebugService.start(
      _hostname,
      webkitDebugger,
      appTab.url,
      _assetHandler,
      appInstanceId,
      _logWriter,
      onResponse: _verbose
          ? (response) {
              if (response['error'] == null) return;
              _logWriter(Level.WARNING,
                  'VmService proxy responded with an error:\n$response');
            }
          : null,
      useSse: false,
    );
  }

  Future<AppDebugServices> loadAppServices(String appId, String instanceId) =>
      _servicesByAppId.putIfAbsent(appId, () async {
        var debugService =
            await startDebugService(await _chromeConnection(), instanceId);
        var appServices = await _createAppDebugServices(appId, debugService);
        unawaited(appServices.chromeProxyService.remoteDebugger.onClose.first
            .whenComplete(() {
          appServices.close();
          _servicesByAppId.remove(appId);
          _logWriter(
              Level.INFO,
              'Stopped debug service on '
              'ws://${debugService.hostname}:${debugService.port}\n');
        }));
        return appServices;
      });

  void _handleConnection(SseConnection injectedConnection) {
    _injectedConnections.add(injectedConnection);
    String appId;
    injectedConnection.stream.listen((data) async {
      try {
        var message = serializers.deserialize(jsonDecode(data));
        if (message is DevToolsRequest) {
          await _handleDebugRequest(message, injectedConnection, appId);
        } else if (message is ConnectRequest) {
          // We need to handle this error state synchronously and assign to
          // [appId] so we do it outside of the `_handleConnectRequest` method.
          if (appId != null) {
            throw StateError('Duplicate connection request from the same app. '
                'Please file an issue at '
                'https://github.com/dart-lang/webdev/issues/new.');
          }
          appId = message.appId;

          await _handleConnectRequest(message, injectedConnection);
        } else if (message is IsolateExit) {
          await _handleIsolateExit(message);
        } else if (message is IsolateStart) {
          await _handleIsolateStart(message, injectedConnection);
        } else if (message is RunResponse) {
          await _handleRunResponse(message);
        }
      } catch (e, s) {
        // Most likely the app disconnected in the middle of us responding,
        // but we will try and send an error response back to the page just in
        // case it is still running.
        try {
          injectedConnection.sink
              .add(jsonEncode(serializers.serialize(ErrorResponse((b) => b
                ..error = '$e'
                ..stackTrace = '$s'))));
        } on StateError catch (_) {
          // The sink has already closed (app is disconnected), swallow the
          // error.
        }
      }
    });

    unawaited(injectedConnection.sink.done.then((_) async {
      _injectedConnections.remove(injectedConnection);
      if (appId != null) {
        var services = await _servicesByAppId[appId];
        services?.connectedInstanceId = null;
        services?.chromeProxyService?.destroyIsolate();
      }
    }));
  }

  Future<void> _handleDebugRequest(DevToolsRequest message,
      SseConnection sseConnection, String connectedAppId) async {
    if (_devTools == null) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..error = 'Debugging is not enabled.\n\n'
                'If you are using webdev please pass the --debug flag.\n'
                'Otherwise check the docs for the tool you are using.'))));
      return;
    }

    if (connectedAppId != message.appId) {
      sseConnection.sink.add(jsonEncode(serializers.serialize(DevToolsResponse(
          (b) => b
            ..success = false
            ..error =
                'App ID has changed since the connection was established. '
                    'Please file an issue at '
                    'https://github.com/dart-lang/webdev/issues/new.'))));
      return;
    }

    AppDebugServices appServices;
    try {
      appServices = await loadAppServices(message.appId, message.instanceId);
    } catch (_) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..error = 'Unable to connect debug services to your '
                'application. Most likely this means you are trying to '
                'load in a different Chrome window than was launched by '
                'your development tool.'))));
      return;
    }

    // Check if we are already running debug services for a different
    // instance of this app.
    if (appServices.connectedInstanceId != null &&
        appServices.connectedInstanceId != message.instanceId) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..error = 'This app is already being debugged in a different tab. '
                'Please close that tab or switch to it.'))));
      return;
    }

    // If you load the same app in a different tab then we need to throw
    // away our old services and start new ones.
    if (!(await _isCorrectTab(
        message.instanceId, appServices.chromeProxyService.remoteDebugger))) {
      unawaited(appServices.close());
      unawaited(_servicesByAppId.remove(message.appId));
      appServices = await loadAppServices(message.appId, message.instanceId);
    }

    sseConnection.sink.add(jsonEncode(
        serializers.serialize(DevToolsResponse((b) => b..success = true))));

    appServices.connectedInstanceId = message.instanceId;
    await appServices.chromeProxyService.remoteDebugger
        .sendCommand('Target.createTarget', params: {
      'newWindow': true,
      'url': Uri(
          scheme: 'http',
          host: _devTools.hostname,
          port: _devTools.port,
          queryParameters: {'uri': appServices.debugService.uri}).toString(),
    });
  }

  Future<void> _handleConnectRequest(
      ConnectRequest message, SseConnection sseConnection) async {
    // After a page refresh, reconnect to the same app services if they
    // were previously launched and create the new isolate.
    var services = await _servicesByAppId[message.appId];
    if (services != null && services.connectedInstanceId == null) {
      // Re-connect to the previous instance if its in the same tab,
      // otherwise do nothing for now.
      if (await _isCorrectTab(
          message.instanceId, services.chromeProxyService.remoteDebugger)) {
        services.connectedInstanceId = message.instanceId;
        await services.chromeProxyService.createIsolate();
      }
    }

    _connectedApps.add(AppConnection(message, sseConnection));
  }

  Future<void> _handleIsolateExit(IsolateExit message) async {
    (await loadAppServices(message.appId, message.instanceId))
        ?.chromeProxyService
        ?.destroyIsolate();
  }

  Future<void> _handleIsolateStart(
      IsolateStart message, SseConnection sseConnection) async {
    if (_enableDebugging) {
      await (await loadAppServices(message.appId, message.instanceId))
          ?.chromeProxyService
          ?.createIsolate();
    }
    // [IsolateStart] events are the result of a Hot Restart.
    // Run the application after the Isolate has been created.
    sseConnection.sink.add(jsonEncode(serializers.serialize(RunRequest())));
  }

  Future<void> _handleRunResponse(RunResponse message) async {
    if (_enableDebugging) {
      await (await loadAppServices(message.appId, message.instanceId))
          ?.chromeProxyService
          ?.resumeFromStart();
    }
  }

  void _listen() async {
    var injectedConnections = _sseHandler.connections;
    while (await injectedConnections.hasNext) {
      _handleConnection(await injectedConnections.next);
    }
  }

  Future<AppDebugServices> _createAppDebugServices(
      String appId, DebugService debugService) async {
    _logWriter(
        Level.INFO,
        'Debug service listening on '
        '${debugService.uri}\n');
    var webdevClient = await DwdsVmClient.create(debugService);
    return AppDebugServices(debugService, webdevClient);
  }

  void _listenForDebugExtension() async {
    while (await _extensionBackend.connections.hasNext) {
      _startExtensionDebugService();
    }
  }

  /// Starts a [DebugService] for Dart Debug Extension.
  void _startExtensionDebugService() async {
    var _extensionDebugger = await _extensionBackend.extensionDebugger;
    // Waits for a `DevToolsRequest` to be sent from the extension background
    // when the extension is clicked.
    _extensionDebugger.devToolsRequestStream.listen((devToolsRequest) async {
      var appServices =
          await _servicesByAppId.putIfAbsent(devToolsRequest.appId, () async {
        var debugService = await DebugService.start(
          _hostname,
          _extensionDebugger,
          devToolsRequest.tabUrl,
          _assetHandler,
          devToolsRequest.appId,
          _logWriter,
          onResponse: _verbose
              ? (response) {
                  if (response['error'] == null) return;
                  _logWriter(Level.WARNING,
                      'VmService proxy responded with an error:\n$response');
                }
              : null,
          useSse: true,
        );
        var appServices =
            await _createAppDebugServices(devToolsRequest.appId, debugService);
        unawaited(appServices.chromeProxyService.remoteDebugger.onClose.first
            .whenComplete(() {
          appServices.chromeProxyService.destroyIsolate();
          appServices.close();
          _servicesByAppId.remove(devToolsRequest.appId);
          _logWriter(
              Level.INFO,
              'Stopped debug service on '
              '${appServices.debugService.uri}\n');
        }));
        extensionDebugConnections.add(DebugConnection(appServices));
        return appServices;
      });
      await _extensionDebugger.sendCommand('Target.createTarget', params: {
        'newWindow': true,
        'url': Uri(
            scheme: 'http',
            host: _devTools.hostname,
            port: _devTools.port,
            queryParameters: {'uri': appServices.debugService.uri}).toString(),
      });
    });
  }
}

/// Checks if connection of [remoteDebugger] is running the app with [instanceId].
Future<bool> _isCorrectTab(
    String instanceId, RemoteDebugger remoteDebugger) async {
  var result = await remoteDebugger.evaluate(r'window["$dartAppInstanceId"];');
  return result.value == instanceId;
}
