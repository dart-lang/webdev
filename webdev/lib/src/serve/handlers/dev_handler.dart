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
import 'package:vm_service_lib/vm_service_lib.dart';

import '../../serve/utils.dart';
import '../data/devtools_request.dart';
import '../data/serializers.dart' as webdev;
import '../debugger/devtools.dart';
import '../handlers/asset_handler.dart';

/// SSE handler to enable development features like hot reload and
/// opening DevTools.
class DevHandler {
  StreamSubscription _sub;
  final SseHandler _sseHandler = SseHandler(Uri.parse(r'/$sseHandler'));
  final _connections = Set<SseConnection>();
  final Future<DevTools> _devtoolsFuture;
  final AssetHandler _assetHandler;

  DevHandler(Stream<BuildResult> buildResults, this._devtoolsFuture,
      this._assetHandler) {
    _sub = buildResults.listen(_emitBuildResults);
    _listen();
  }

  Handler get handler => _sseHandler.handler;

  Future<void> close() async {
    await _sub.cancel();
    for (var connection in _connections) {
      connection.close();
    }
  }

  void _emitBuildResults(BuildResult result) {
    if (result.status != BuildStatus.succeeded) return;
    for (var connection in _connections) {
      connection.sink.add(jsonEncode(serializers.serialize(result)));
    }
  }

  void _handleConnection(SseConnection connection) {
    _connections.add(connection);
    DebugService debugService;
    _WebdevClient webdevClient;
    connection.stream.listen((data) async {
      var message = webdev.serializers.deserialize(jsonDecode(data));
      if (message is DevToolsRequest) {
        var devTools = await _devtoolsFuture;
        if (devTools == null) return;
        var chrome = devTools.chrome;
        if (debugService == null) {
          debugService = await DebugService.start(
            devTools.hostname,
            chrome.chromeConnection,
            _assetHandler.getRelativeAsset,
            message.url,
          );

          webdevClient = await _WebdevClient.create(debugService);

          colorLog(
              Level.INFO,
              'Debug service listening on '
              'ws://${debugService.hostname}:${debugService.port}\n');
        }
        await chrome.chromeConnection
            // Chrome protocol for spawning a new tab.
            .getUrl('json/new/?http://${devTools.hostname}:${devTools.port}'
                '/?port=${debugService.port}');
      }
    });
    unawaited(connection.onClose.then((_) async {
      if (debugService != null) {
        await debugService.close();
        webdevClient.close();

        colorLog(
            Level.INFO,
            'Stopped debug service on '
            'ws://${debugService.hostname}:${debugService.port}\n');
        debugService = null;
        webdevClient = null;
      }
      _connections.remove(connection);
    }));
  }

  void _listen() async {
    var connections = _sseHandler.connections;
    while (await connections.hasNext) {
      _handleConnection(await connections.next);
    }
  }
}

// A client of the vm service that registers some custom extensions like
// hotRestart.
class _WebdevClient {
  final VmService _client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object>> _responseController;

  _WebdevClient(
      this._client, this._requestController, this._responseController);

  static Future<_WebdevClient> create(DebugService debugService) async {
    // Set up hot restart as an extension.
    var requestController = StreamController<Map<String, Object>>();
    var responseController = StreamController<Map<String, Object>>();
    VmServerConnection(requestController.stream, responseController.sink,
        debugService.serviceExtensionRegistry, debugService.chromeProxyService);
    var client = VmService(
        responseController.stream.map(jsonEncode),
        (request) => requestController.sink
            .add(jsonDecode(request) as Map<String, dynamic>));
    client.registerServiceCallback('hotRestart', (request) async {
      debugService.chromeProxyService.destroyIsolate();
      await debugService.chromeProxyService.tabConnection.runtime.sendCommand(
          'Runtime.evaluate',
          params: {'expression': r'$dartHotRestart();', 'awaitPromise': true});
      unawaited(debugService.chromeProxyService.createIsolate());
      return {'result': Success().toJson()};
    });
    await client.registerService('hotRestart', 'WebDev');

    // TODO: Remove this (we don't actually support it yet) once devtools
    // has published a new version.
    client.registerServiceCallback('reloadSources', (request) async {
      throw UnsupportedError(
          'Hot Reload is not yet supported for flutter web, try hot restart.');
    });
    await client.registerService('reloadSources', 'WebDev');

    return _WebdevClient(client, requestController, responseController);
  }

  void close() {
    _requestController.close();
    _responseController.close();
    _client.dispose();
  }
}
