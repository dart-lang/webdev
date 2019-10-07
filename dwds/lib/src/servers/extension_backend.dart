// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dwds/src/servers/extension_debugger.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf_io.dart';
import 'package:sse/server/sse_handler.dart';

final _sseHandler = SseHandler(Uri.parse('/\$debug'));

/// A backend for the Dart Debug Extension.
///
/// Sets up an SSE handler to communicate with the extension background.
/// Uses that SSE channel to create an [ExtensionDebugger].
class ExtensionBackend {
  final String hostname;
  final int port;
  final HttpServer _server;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  ExtensionBackend._(this.hostname, this.port, this._server);

  // Starts the backend on an open port.
  static Future<ExtensionBackend> start(String hostname) async {
    var server = await HttpMultiServer.bind(hostname, 0);
    serveRequests(server, _sseHandler.handler);
    return ExtensionBackend._(server.address.host, server.port, server);
  }

  Future<void> close() => _closed ??= _server.close();

  StreamQueue<SseConnection> connections = _sseHandler.connections;

  Future<ExtensionDebugger> get extensionDebugger async =>
      ExtensionDebugger(await connections.next);
}
