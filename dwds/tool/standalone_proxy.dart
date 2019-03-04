// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:args/args.dart';
import 'package:dwds/src/chrome_proxy_service.dart';
import 'package:webdev/src/serve/chrome.dart';
import 'package:webdev/src/serve/utils.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Shared debugService for all clients.
ChromeProxyService debugService;
final serviceExtensionRegistry = ServiceExtensionRegistry();

/// Sets up a web app with the debug service.
///
/// - Opens up chrome with a specified app uri and the debug port enabled.
/// - Runs the proxy service on a specified host and port, or a random port if
///   not specified.
void main(List<String> args) async {
  var parser = ArgParser()
    ..addOption('app-uri')
    ..addOption('host', defaultsTo: 'localhost')
    ..addOption('port');
  var parsed = parser.parse(args);
  var appUri = parsed['app-uri'] as String;
  if (appUri == null) {
    throw ArgumentError('Must provide an --app-uri to load in chrome');
  }

  var chrome = await Chrome.start([appUri]);

  debugService =
      await ChromeProxyService.create(chrome.chromeConnection, appUri);

  var cascade = shelf.Cascade().add(webSocketHandler(handleNewConnection));

  var host = parsed['host'] as String;
  int port;
  if (parsed['port'] != null) {
    port = int.parse(parsed['port'] as String);
  } else {
    port = await findUnusedPort();
  }

  await serve(cascade.handler, host, port);
  print('Debug service running at ws://$host:$port');
}

/// Creates a new VmServer instance for each client, reusing the global service
/// object.
void handleNewConnection(WebSocketChannel webSocket, String protocol) {
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

  VmServerConnection(inputStream, responseController.sink,
      serviceExtensionRegistry, debugService);
}
