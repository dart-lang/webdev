// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/src/servers/extension_debugger.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf_io.dart';
import 'package:sse/server/sse_handler.dart';

SseHandler _sseHandler = SseHandler(Uri.parse('/test'));

/// A backend for the Dart Debug Extension which sets up an SSE handler.
class ExtensionBackend {
  final String hostname;
  final int port;
  final HttpServer _server;
  ExtensionBackend._(this.hostname, this.port, this._server);

  // Starts the backend on an open port.
  static Future<ExtensionBackend> start() async {
    var server = await HttpMultiServer.bind('localhost', 0);
    serveRequests(server, _sseHandler.handler);
    return ExtensionBackend._(server.address.host, server.port, server);
  }

  Future<void> close() async {
    await _server.close();
  }

  var connections = _sseHandler.connections;
  Future<ExtensionDebugger> get extensionDebugger async =>
      ExtensionDebugger(await connections.next);
}
