// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/serializers.dart';
import 'package:dwds/service.dart';
import 'package:logging/logging.dart';
import 'package:pedantic/pedantic.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../logging.dart';
import '../chrome.dart';
import '../data/connect_request.dart';
import '../data/devtools_request.dart';
import '../data/run_request.dart';
import '../data/serializers.dart' as webdev;
import '../debugger/app_debug_services.dart';
import '../debugger/devtools.dart';
import '../debugger/webdev_vm_client.dart';
import '../handlers/asset_handler.dart';

/// SSE handler to enable development features like hot reload and
/// opening DevTools.
class DevHandler {
  StreamSubscription _sub;
  final SseHandler _sseHandler = SseHandler(Uri.parse(r'/$sseHandler'));
  final _connections = Set<SseConnection>();
  final DevTools _devTools;
  final AssetHandler _assetHandler;
  final String _hostname;
  final _connectedApps = StreamController<DevConnection>.broadcast();
  final _servicesByAppId = <String, Future<AppDebugServices>>{};
  final Stream<BuildResult> buildResults;

  Stream<DevConnection> get connectedApps => _connectedApps.stream;

  DevHandler(
      this.buildResults, this._devTools, this._assetHandler, this._hostname) {
    _sub = buildResults.listen(_emitBuildResults);
    _listen();
  }

  Handler get handler => _sseHandler.handler;

  Future<void> close() async {
    await _sub.cancel();
    // We listen for connections to close and remove them from the connections
    // set. Therefore we shouldn't asynchronously iterate through the
    // connections.
    await Future.wait(
        _connections.map((connection) => connection.sink.close()));
    await Future.wait(_servicesByAppId.values.map((futureServices) async {
      await (await futureServices).close();
    }));
    _servicesByAppId.clear();
  }

  void _emitBuildResults(BuildResult result) {
    if (result.status != BuildStatus.succeeded) return;
    for (var connection in _connections) {
      connection.sink.add(jsonEncode(serializers.serialize(result)));
    }
  }

  // TODO(https://github.com/dart-lang/webdev/issues/202) - Refactor so this is
  // a getter and is created immediately.
  Future<DebugService> startDebugService(
      ChromeConnection chromeConnection, String appInstanceId) async {
    return DebugService.start(
      _hostname,
      chromeConnection,
      _assetHandler.getRelativeAsset,
      appInstanceId,
    );
  }

  Future<AppDebugServices> loadAppServices(String appId, String instanceId) =>
      _servicesByAppId.putIfAbsent(
          appId, () => _createAppDebugServices(appId, instanceId));

  void _handleConnection(SseConnection connection) {
    _connections.add(connection);
    String appId;
    connection.stream.listen((data) async {
      var message = webdev.serializers.deserialize(jsonDecode(data));
      if (message is DevToolsRequest) {
        if (_devTools == null) {
          connection.sink.add(jsonEncode(webdev.serializers.serialize(
              DevToolsResponse((b) => b
                ..success = false
                ..error =
                    'Debugging is not enabled, please pass the --debug flag '
                        'when starting webdev.'))));
          return;
        }
        if (appId != message.appId) {
          connection.sink.add(jsonEncode(webdev.serializers.serialize(
              DevToolsResponse((b) => b
                ..success = false
                ..error =
                    'App ID has changed since the connection was established. '
                        'Please file an issue at '
                        'https://github.com/dart-lang/webdev/issues/new.'))));
          return;
        }

        AppDebugServices appServices;
        try {
          appServices =
              await loadAppServices(message.appId, message.instanceId);
        } catch (_) {
          connection.sink.add(
              jsonEncode(webdev.serializers.serialize(DevToolsResponse((b) => b
                ..success = false
                ..error = 'Webdev was unable to connect debug services to your '
                    'application. Most likely this means you are trying to '
                    'load in a different Chrome window than was launched by '
                    'webdev.'))));
          return;
        }

        // Check if we are already running debug services for a different
        // instance of this app.
        if (appServices.connectedInstanceId != null &&
            appServices.connectedInstanceId != message.instanceId) {
          connection.sink.add(jsonEncode(webdev.serializers.serialize(
              DevToolsResponse((b) => b
                ..success = false
                ..error =
                    'This app is already being debugged in a different tab. '
                        'Please close that tab or switch to it.'))));
          return;
        }

        // If you load the same app in a different tab then we need to throw
        // away our old services and start new ones.
        if (!(await _isCorrectTab(message.instanceId,
            appServices.chromeProxyService.tabConnection))) {
          unawaited(appServices.close());
          unawaited(_servicesByAppId.remove(message.appId));
          appServices =
              await loadAppServices(message.appId, message.instanceId);
        }

        connection.sink.add(jsonEncode(webdev.serializers
            .serialize(DevToolsResponse((b) => b..success = true))));

        appServices.connectedInstanceId = message.instanceId;
        await appServices.chromeProxyService.tabConnection.runtime.evaluate(
            'window.open("http://${_devTools.hostname}:${_devTools.port}'
            '/?uri=${appServices.debugService.wsUri}", "", "_blank")');
      } else if (message is ConnectRequest) {
        if (appId != null) {
          throw StateError('Duplicate connection request from the same app. '
              'Please file an issue at '
              'https://github.com/dart-lang/webdev/issues/new.');
        }
        appId = message.appId;

        // After a page refresh, reconnect to the same app services if they
        // were previously launched and create the new isolate.
        var services = await _servicesByAppId[message.appId];
        if (services != null && services.connectedInstanceId == null) {
          // Re-connect to the previous instance if its in the same tab,
          // otherwise do nothing for now.
          if (await _isCorrectTab(
              message.instanceId, services.chromeProxyService.tabConnection)) {
            services.connectedInstanceId = message.instanceId;
            await services.chromeProxyService.createIsolate();
          }
        }

        _connectedApps.add(DevConnection(message, connection));
      }
    });

    unawaited(connection.sink.done.then((_) async {
      _connections.remove(connection);
      if (appId != null) {
        var services = await _servicesByAppId[appId];
        services?.connectedInstanceId = null;
        services?.chromeProxyService?.destroyIsolate();
      }
    }));
  }

  void _listen() async {
    var connections = _sseHandler.connections;
    while (await connections.hasNext) {
      _handleConnection(await connections.next);
    }
  }

  Future<AppDebugServices> _createAppDebugServices(
      String appId, String instanceId) async {
    var chrome = await Chrome.connectedInstance;
    var debugService =
        await startDebugService(chrome.chromeConnection, instanceId);
    logWriter(
        Level.INFO,
        'Debug service listening on '
        '${debugService.wsUri}\n');

    var webdevClient = await WebdevVmClient.create(debugService);
    var appServices = AppDebugServices(chrome, debugService, webdevClient);

    unawaited(
        appServices.chromeProxyService.tabConnection.onClose.first.then((_) {
      appServices.close();
      _servicesByAppId.remove(appId);
      logWriter(
          Level.INFO,
          'Stopped debug service on '
          'ws://${debugService.hostname}:${debugService.port}\n');
    }));

    return appServices;
  }
}

/// Checks if [tabConnection] is running the app with [instanceId].
Future<bool> _isCorrectTab(
    String instanceId, WipConnection tabConnection) async {
  var result =
      await tabConnection.runtime.evaluate(r'window["$dartAppInstanceId"];');
  return result.value == instanceId;
}

class DevConnection {
  final ConnectRequest request;
  final SseConnection _connection;
  var _isStarted = false;
  DevConnection(this.request, this._connection);

  void runMain() {
    if (!_isStarted) {
      _connection.sink
          .add(jsonEncode(webdev.serializers.serialize(RunRequest())));
    }
    _isStarted = true;
  }
}
