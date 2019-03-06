// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import './src/chrome_proxy_service.dart';
import './src/helpers.dart';

void Function(WebSocketChannel, String) _createNewConnectionHandler(
    ChromeProxyService chromeProxyService) {
  return (webSocket, protocol) {
    var responseController = StreamController<Map<String, Object>>();
    webSocket.sink.addStream(responseController.stream.map(jsonEncode));
    var inputStream = webSocket.stream.map((value) {
      if (value is List<int>) {
        value = utf8.decode(value as List<int>);
      } else if (value is! String) {
        throw StateError(
            'Got value with unexpected type ${value.runtimeType} from web '
            'socket, expected a List<int> or String.');
      }
      return jsonDecode(value as String) as Map<String, Object>;
    });

    var serviceExtensionRegistry = ServiceExtensionRegistry();

    VmServerConnection(inputStream, responseController.sink,
        serviceExtensionRegistry, chromeProxyService);
  };
}

/// A Dart Web Debug Service.
///
/// Creates a [ChromeProxyService] from an existing Chrome instance.
class DebugService {
  final String hostname;

  final int port;
  final HttpServer _server;
  DebugService._(this.hostname, this.port, this._server);

  Future<void> close() async {
    await _server.close();
  }

  static Future<DebugService> start(
      String hostname, ChromeConnection chromeConnection, String url) async {
    var chromeProxyService =
        await ChromeProxyService.create(chromeConnection, url);
    var cascade = Cascade()
        .add(webSocketHandler(_createNewConnectionHandler(chromeProxyService)));

    var port = await findUnusedPort();

    var server = await serve(cascade.handler, hostname, port);
    return DebugService._(hostname, port, server);
  }
}
