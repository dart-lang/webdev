// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;
import 'package:sse/server/sse_handler.dart';

SseHandler _sseHandler = SseHandler(Uri.parse('/test'));

/// A debug extension backend which sets up an SSE handler.
///
/// This is still a skeleton. The SSE handler simply sends a simple message and
/// prints the response when a client connects.
class ExtensionBackend {
  String hostname;
  int port;
  HttpServer _server;

  ExtensionBackend._(this.hostname, this.port, this._server) {
    _listen();
  }

  // Starts the backend on an open port.
  static Future<ExtensionBackend> start() async {
    var server = await io.serve(_sseHandler.handler, 'localhost', 0);
    return ExtensionBackend._(server.address.host, server.port, server);
  }

  Future<void> close() async {
    await _server.close();
  }

  void _listen() async {
    var connections = _sseHandler.connections;
    while (await connections.hasNext) {
      var connection = await connections.next;
      connection.sink.add('foo');
      connection.stream.listen(print);
    }
  }
}
