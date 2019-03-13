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
  final Future<DevTools> _devtoolsFuture;
  final AssetHandler _assetHandler;

  StreamQueue<SseConnection> get connections => _sseHandler.connections;

  DevHandler(Stream<BuildResult> buildResults, this._devtoolsFuture,
      this._assetHandler) {
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
  Future<WebdevVmClient> createClient(
      Chrome chrome, String hostname, String appUrl) async {
    var debugService = await DebugService.start(
      hostname,
      chrome.chromeConnection,
      _assetHandler.getRelativeAsset,
      appUrl,
    );

    return await WebdevVmClient.create(debugService);
  }

  void _handleConnection(SseConnection connection) {
    _connections.add(connection);
    // TODO(grouma) - This client should be closed on close.
    WebdevVmClient webdevClient;

    connection.stream.listen((data) async {
      var message = webdev.serializers.deserialize(jsonDecode(data));
      if (message is DevToolsRequest) {
        var devTools = await _devtoolsFuture;
        if (devTools == null) return;
        var chrome = devTools.chrome;
        if (webdevClient == null) {
          webdevClient =
              await createClient(chrome, devTools.hostname, message.url);
          colorLog(
              Level.INFO,
              'Debug service listening on '
              'ws://${webdevClient.hostname}:${webdevClient.port}\n');
        }
        await chrome.chromeConnection
            // Chrome protocol for spawning a new tab.
            .getUrl('json/new/?http://${devTools.hostname}:${devTools.port}'
                '/?port=${webdevClient.port}');
      }
    });
    unawaited(connection.sink.done.then((_) async {
      if (webdevClient != null) {
        await webdevClient.close();
        colorLog(
            Level.INFO,
            'Stopped debug service on '
            'ws://${webdevClient.hostname}:${webdevClient.port}\n');
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
