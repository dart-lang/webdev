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

import '../../serve/chrome.dart';
import '../../serve/logging.dart';
import '../data/connect_request.dart';
import '../data/devtools_request.dart';
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
  final _connectedApps = StreamController<ConnectRequest>.broadcast();
  final _servicesByAppId = <String, Future<AppDebugServices>>{};
  final Stream<BuildResult> buildResults;

  Stream<ConnectRequest> get connectedApps => _connectedApps.stream;

  DevHandler(
      this.buildResults, this._devTools, this._assetHandler, this._hostname) {
    _sub = buildResults.listen(_emitBuildResults);
    _listen();
  }

  Handler get handler => _sseHandler.handler;

  Future<void> close() async {
    await _sub.cancel();
    for (var connection in _connections) {
      await connection.sink.close();
    }
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
    AppDebugServices appServices;
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

        appServices = await loadAppServices(message.appId, message.instanceId);

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
            appServices.debugService.chromeProxyService.tabConnection))) {
          unawaited(appServices.close());
          unawaited(_servicesByAppId.remove(message.appId));
          appServices =
              await loadAppServices(message.appId, message.instanceId);
        }

        connection.sink.add(jsonEncode(webdev.serializers
            .serialize(DevToolsResponse((b) => b..success = true))));

        appServices.connectedInstanceId = message.instanceId;
        await appServices.chrome.chromeConnection
            // Chrome protocol for spawning a new tab.
            .getUrl('json/new/?http://${_devTools.hostname}:${_devTools.port}'
                '/?port=${appServices.debugService.port}');
      } else if (message is ConnectRequest) {
        _connectedApps.add(message);
        // After a page refresh, reconnect to the same app services if they
        // were previously launched and create the new isolate.
        var services = await _servicesByAppId[message.appId];
        if (services != null && services.connectedInstanceId == null) {
          // Re-connect to the previous instance if its in the same tab,
          // otherwise do nothing for now.
          if (await _isCorrectTab(message.instanceId,
              services.debugService.chromeProxyService.tabConnection)) {
            appServices = services;
            appServices.connectedInstanceId = message.instanceId;
            await appServices.debugService.chromeProxyService.createIsolate();
          }
        }
      }
    });

    unawaited(connection.sink.done.then((_) async {
      _connections.remove(connection);
      appServices?.connectedInstanceId = null;
      appServices?.debugService?.chromeProxyService?.destroyIsolate();
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
    logHandler(
        Level.INFO,
        'Debug service listening on '
        'ws://${debugService.hostname}:${debugService.port}\n');

    var webdevClient = await WebdevVmClient.create(debugService);
    var appServices = AppDebugServices(chrome, debugService, webdevClient);

    unawaited(
        debugService.chromeProxyService.tabConnection.onClose.first.then((_) {
      appServices.close();
      _servicesByAppId.remove(appId);
      logHandler(
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
