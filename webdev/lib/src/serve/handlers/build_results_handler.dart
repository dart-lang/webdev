// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/serializers.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final _buildResultsProtocol = r'$buildResults';

/// Web socket handler to inform clients of build results.
class BuildResultsHandler {
  final _connections = Set<WebSocketChannel>();
  StreamSubscription _sub;

  Handler _handler;
  BuildResultsHandler(Stream<BuildResult> buildResults) {
    _sub = buildResults.listen(_emitBuildResults);
    _handler =
        webSocketHandler(_handleConnection, protocols: [_buildResultsProtocol]);
  }

  Handler get handler => _handler;

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

  void _handleConnection(WebSocketChannel webSocket, String protocol) async {
    _connections.add(webSocket);
    await webSocket.stream.drain();
    _connections.remove(webSocket);
  }
}
