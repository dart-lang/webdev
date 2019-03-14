// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/serializers.dart';
import 'package:dwds/service.dart';
import 'package:logging/logging.dart';
import 'package:pedantic/pedantic.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../serve/chrome.dart';
import '../../serve/utils.dart';
import '../data/devtools_request.dart';
import '../data/serializers.dart' as webdev;
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

  StreamQueue<SseConnection> get connections => _sseHandler.connections;

  DevHandler(Stream<BuildResult> buildResults, this._devTools,
      this._assetHandler, this._hostname) {
    _sub = buildResults.listen(_emitBuildResults);
    _listen();
  }

  Handler get handler => _sseHandler.handler;

  Future<void> close() async {
    await _sub.cancel();
    for (var connection in _connections) {
      await connection.sink.close();
    }
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
      ChromeConnection chromeConnection, String appUrl) async {
    return await DebugService.start(
      _hostname,
      chromeConnection,
      _assetHandler.getRelativeAsset,
      appUrl,
    );
  }

  void _handleConnection(SseConnection connection) {
    _connections.add(connection);
    // TODO(grouma) - This client should be closed on close.
    WebdevVmClient webdevClient;
    DebugService debugService;
    connection.stream.listen((data) async {
      var message = webdev.serializers.deserialize(jsonDecode(data));
      if (message is DevToolsRequest) {
        if (_devTools == null) return;
        var chrome = await Chrome.connectedInstance;
        if (debugService == null) {
          debugService =
              await startDebugService(chrome.chromeConnection, message.url);
          colorLog(
              Level.INFO,
              'Debug service listening on '
              'ws://${debugService.hostname}:${debugService.port}\n');
        }

        webdevClient = await WebdevVmClient.create(debugService);
        await chrome.chromeConnection
            // Chrome protocol for spawning a new tab.
            .getUrl('json/new/?http://${_devTools.hostname}:${_devTools.port}'
                '/?port=${debugService.port}');
      }
    });
    unawaited(connection.sink.done.then((_) async {
      if (debugService != null) {
        await debugService.close();
        await webdevClient.close();
        colorLog(
            Level.INFO,
            'Stopped debug service on '
            'ws://${debugService.hostname}:${debugService.port}\n');
        webdevClient = null;
        debugService = null;
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
