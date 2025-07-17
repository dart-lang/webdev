// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dds/dds_launcher.dart';
import 'package:dwds/src/connections/app_connection.dart';

import 'package:dwds/src/services/web_socket_proxy_service.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:logging/logging.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Defines callbacks for sending messages to the connected client.
/// Returns the number of clients the request was successfully sent to.
typedef SendClientRequest = int Function(Object request);

// Connection control for WebSocket clients
bool _acceptNewConnections = true;
int _clientsConnected = 0;

/// WebSocket-based debug service for web debugging.
class WebSocketDebugService {
  final String hostname;
  final int port;
  final String authToken;
  final HttpServer _server;
  final WebSocketProxyService _webSocketProxyService;
  final ServiceExtensionRegistry _serviceExtensionRegistry;

  Future<void>? _closed;
  DartDevelopmentServiceLauncher? _dds;

  WebSocketDebugService._(
    this.hostname,
    this.port,
    this.authToken,
    this._webSocketProxyService,
    this._serviceExtensionRegistry,
    this._server,
  );

  /// Returns the WebSocketProxyService instance.
  WebSocketProxyService get webSocketProxyService => _webSocketProxyService;

  /// Returns the ServiceExtensionRegistry instance.
  ServiceExtensionRegistry get serviceExtensionRegistry =>
      _serviceExtensionRegistry;

  /// Closes the debug service and associated resources.
  Future<void> close() =>
      _closed ??= Future.wait([
        _server.close(),
        if (_dds != null) _dds!.shutdown(),
      ]);

  /// Starts DDS (Dart Development Service).
  Future<DartDevelopmentServiceLauncher> startDartDevelopmentService({
    int? ddsPort,
  }) async {
    const timeout = Duration(seconds: 10);

    try {
      _dds = await DartDevelopmentServiceLauncher.start(
        remoteVmServiceUri: Uri(
          scheme: 'http',
          host: hostname,
          port: port,
          path: authToken,
        ),
        serviceUri: Uri(scheme: 'http', host: hostname, port: ddsPort ?? 0),
      ).timeout(timeout);
    } catch (e) {
      throw Exception('Failed to start DDS: $e');
    }
    return _dds!;
  }

  String get uri =>
      Uri(scheme: 'ws', host: hostname, port: port, path: authToken).toString();

  static Future<WebSocketDebugService> start(
    String hostname,
    AppConnection appConnection, {
    required SendClientRequest sendClientRequest,
  }) async {
    final authToken = _makeAuthToken();
    final serviceExtensionRegistry = ServiceExtensionRegistry();

    final webSocketProxyService = await WebSocketProxyService.create(
      sendClientRequest,
      appConnection,
    );

    final handler = _createWebSocketHandler(
      serviceExtensionRegistry,
      webSocketProxyService,
    );

    final server = await startHttpServer(hostname, port: 0);
    serveHttpRequests(server, handler, (e, s) {
      Logger('WebSocketDebugService').warning('Error serving requests', e);
    });

    return WebSocketDebugService._(
      server.address.host,
      server.port,
      authToken,
      webSocketProxyService,
      serviceExtensionRegistry,
      server,
    );
  }

  /// Creates the WebSocket handler for incoming connections.
  static dynamic _createWebSocketHandler(
    ServiceExtensionRegistry serviceExtensionRegistry,
    WebSocketProxyService webSocketProxyService,
  ) {
    return webSocketHandler((WebSocketChannel webSocket) {
      if (!_acceptNewConnections) {
        webSocket.sink.add(
          jsonEncode({
            'error': 'Cannot connect: another service has taken control.',
          }),
        );
        webSocket.sink.close();
        return;
      }

      final responseController = StreamController<Map<String, Object?>>();
      webSocket.sink.addStream(responseController.stream.map(jsonEncode));

      final inputStream = webSocket.stream.map((value) {
        if (value is List<int>) {
          value = utf8.decode(value);
        } else if (value is! String) {
          throw StateError(
            'Unexpected value type from web socket: ${value.runtimeType}',
          );
        }
        return Map<String, Object>.from(jsonDecode(value));
      });

      ++_clientsConnected;
      VmServerConnection(
        inputStream,
        responseController.sink,
        serviceExtensionRegistry,
        webSocketProxyService,
      ).done.whenComplete(() {
        --_clientsConnected;
        if (!_acceptNewConnections && _clientsConnected == 0) {
          _acceptNewConnections = true;
        }
      });
    });
  }
}

// Creates a random auth token for more secure connections.
String _makeAuthToken() {
  final tokenBytes = 8;
  final bytes = Uint8List(tokenBytes);
  final random = Random.secure();
  for (var i = 0; i < tokenBytes; i++) {
    bytes[i] = random.nextInt(256);
  }
  return base64Url.encode(bytes);
}
