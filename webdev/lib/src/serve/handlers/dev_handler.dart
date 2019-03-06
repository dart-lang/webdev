// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/serializers.dart';
import 'package:pedantic/pedantic.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';

import '../data/devtools_request.dart';
import '../data/serializers.dart' as webdev;
import '../debugger/devtools.dart';
import '../debugger/service.dart';

/// Web socket handler to enable development features like hot reload and
/// opening DevTools.
class DevHandler {
  StreamSubscription _sub;
  final SseHandler _sseHandler = SseHandler(Uri.parse(r'/$sseHandler'));
  final _connections = Set<SseConnection>();
  final Future<DevTools> _devtoolsFuture;

  DevHandler(Stream<BuildResult> buildResults, this._devtoolsFuture) {
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
    connection.stream.listen((data) async {
      var message = webdev.serializers.deserialize(jsonDecode(data));
      if (message is DevToolsRequest) {
        var devTools = await _devtoolsFuture;
        if (devTools == null) return;
        var chrome = devTools.chrome;
        debugService ??= await DebugService.start(
          devTools.hostname,
          chrome,
          message.url,
        );
        await chrome.chromeConnection
            .getUrl('json/new/?http://${devTools.hostname}:${devTools.port}'
                '/?port=${debugService.port}');
      }
    });
    unawaited(connection.onClose.then((_) async {
      await debugService?.close();
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
