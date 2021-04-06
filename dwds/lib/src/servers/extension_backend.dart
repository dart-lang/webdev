// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:io';

import 'package:async/async.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';

import '../../data/extension_request.dart';
import '../handlers/socket_connections.dart';
import 'extension_debugger.dart';

const authenticationResponse = 'Dart Debug Authentication Success!\n\n'
    'You can close this tab and launch the Dart Debug Extension again.';

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

  ExtensionBackend._(
      SocketHandler _socketHandler, this.hostname, this.port, this._server)
      : connections = _socketHandler.connections;

  // Starts the backend on an open port.
  static Future<ExtensionBackend> start(
      SocketHandler _socketHandler, String hostname) async {
    var cascade = Cascade();
    cascade = cascade.add((request) {
      if (request.url.path == authenticationPath) {
        return Response.ok(authenticationResponse, headers: {
          'Access-Control-Allow-Origin': request.headers['origin'],
          'Access-Control-Allow-Credentials': 'true'
        });
      }
      return Response.notFound('');
    }).add(_socketHandler.handler);
    var server = await HttpMultiServer.bind(hostname, 0);
    serveRequests(server, cascade.handler);
    return ExtensionBackend._(
        _socketHandler, server.address.host, server.port, server);
  }

  Future<void> close() => _closed ??= _server.close();

  final StreamQueue<SocketConnection> connections;

  Future<ExtensionDebugger> get extensionDebugger async =>
      ExtensionDebugger(await connections.next);
}
