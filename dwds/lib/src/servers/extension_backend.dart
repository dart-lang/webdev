// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf_io.dart';
import 'package:sse/server/sse_handler.dart';

SseHandler _sseHandler = SseHandler(Uri.parse('/test'));

/// A backend for the Dart Debug Extension which sets up an SSE handler.
///
/// The SSE handler simply sends a simple message and prints the response when
/// a client connects.
class ExtensionBackend {
  String hostname;
  int port;
  HttpServer _server;

  ExtensionBackend._(this.hostname, this.port, this._server) {
    _listen();
  }

  // Starts the backend on an open port.
  static Future<ExtensionBackend> start() async {
    //var server = await io.serve(_sseHandler.handler, 'localhost', 0);
    var server = await HttpMultiServer.bind('localhost', 0);
    serveRequests(server, _sseHandler.handler);
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
