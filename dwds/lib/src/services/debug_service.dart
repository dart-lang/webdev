// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http_multi_server/http_multi_server.dart';
import 'package:pedantic/pedantic.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart' hide Response;
import 'package:shelf/shelf_io.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:vm_service/vm_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../dwds.dart';
import '../debugging/execution_context.dart';
import '../debugging/metadata/provider.dart';
import '../debugging/remote_debugger.dart';
import '../readers/asset_reader.dart';
import '../utilities/shared.dart';
import 'chrome_proxy_service.dart';
import 'expression_compiler.dart';

void Function(WebSocketChannel, String) _createNewConnectionHandler(
  ChromeProxyService chromeProxyService,
  ServiceExtensionRegistry serviceExtensionRegistry, {
  void Function(Map<String, dynamic>) onRequest,
  void Function(Map<String, dynamic>) onResponse,
}) {
  return (webSocket, protocol) {
    var responseController = StreamController<Map<String, Object>>();
    webSocket.sink.addStream(responseController.stream.map((response) {
      if (onResponse != null) onResponse(response);
      return jsonEncode(response);
    }));
    var inputStream = webSocket.stream.map((value) {
      if (value is List<int>) {
        value = utf8.decode(value as List<int>);
      } else if (value is! String) {
        throw StateError(
            'Got value with unexpected type ${value.runtimeType} from web '
            'socket, expected a List<int> or String.');
      }
      var request = jsonDecode(value as String) as Map<String, Object>;
      if (onRequest != null) onRequest(request);
      return request;
    });

    VmServerConnection(inputStream, responseController.sink,
        serviceExtensionRegistry, chromeProxyService);
  };
}

Future<void> _handleSseConnections(
  SseHandler handler,
  ChromeProxyService chromeProxyService,
  ServiceExtensionRegistry serviceExtensionRegistry, {
  void Function(Map<String, dynamic>) onRequest,
  void Function(Map<String, dynamic>) onResponse,
}) async {
  while (await handler.connections.hasNext) {
    var connection = await handler.connections.next;
    var responseController = StreamController<Map<String, Object>>();
    var sub = responseController.stream.map((response) {
      if (onResponse != null) onResponse(response);
      return jsonEncode(response);
    }).listen(connection.sink.add);
    unawaited(chromeProxyService.remoteDebugger.onClose.first.whenComplete(() {
      connection.sink.close();
      sub.cancel();
    }));
    var inputStream = connection.stream.map((value) {
      var request = jsonDecode(value) as Map<String, Object>;
      if (onRequest != null) onRequest(request);
      return request;
    });
    var vmServerConnection = VmServerConnection(inputStream,
        responseController.sink, serviceExtensionRegistry, chromeProxyService);
    unawaited(vmServerConnection.done.whenComplete(sub.cancel));
  }
}

/// A Dart Web Debug Service.
///
/// Creates a [ChromeProxyService] from an existing Chrome instance.
class DebugService {
  final VmServiceInterface chromeProxyService;
  final String hostname;
  final ServiceExtensionRegistry serviceExtensionRegistry;
  final int port;
  final HttpServer _server;
  final String _authToken;
  final bool _useSse;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  DebugService._(
      this.chromeProxyService,
      this.hostname,
      this.port,
      this._authToken,
      this.serviceExtensionRegistry,
      this._server,
      this._useSse);

  Future<void> close() => _closed ??= _server.close();

  String get uri => _useSse
      ? Uri(
              scheme: 'sse',
              host: hostname,
              port: port,
              path: '$_authToken/\$debugHandler')
          .toString()
      : Uri(scheme: 'ws', host: hostname, port: port, path: '$_authToken')
          .toString();

  static Future<DebugService> start(
      String hostname,
      RemoteDebugger remoteDebugger,
      ExecutionContext executionContext,
      String tabUrl,
      AssetReader assetReader,
      LoadStrategy loadStrategy,
      MetadataProvider metadataProvider,
      AppConnection appConnection,
      LogWriter logWriter,
      {void Function(Map<String, dynamic>) onRequest,
      void Function(Map<String, dynamic>) onResponse,
      bool useSse,
      ExpressionCompiler expressionCompiler}) async {
    useSse ??= false;
    var chromeProxyService = await ChromeProxyService.create(
        remoteDebugger,
        tabUrl,
        assetReader,
        loadStrategy,
        metadataProvider,
        appConnection,
        logWriter,
        executionContext,
        expressionCompiler);
    var authToken = _makeAuthToken();
    var serviceExtensionRegistry = ServiceExtensionRegistry();
    Handler handler;
    if (useSse) {
      var sseHandler = SseHandler(Uri.parse('/$authToken/\$debugHandler'));
      handler = sseHandler.handler;
      unawaited(_handleSseConnections(
          sseHandler, chromeProxyService, serviceExtensionRegistry,
          onRequest: onRequest, onResponse: onResponse));
    } else {
      var innerHandler = webSocketHandler(_createNewConnectionHandler(
          chromeProxyService, serviceExtensionRegistry,
          onRequest: onRequest, onResponse: onResponse));
      handler = (shelf.Request request) {
        if (request.url.pathSegments.first != authToken) {
          return shelf.Response.forbidden('Incorrect auth token');
        }
        return innerHandler(request);
      };
    }
    var port = await findUnusedPort();
    var server = await HttpMultiServer.bind(hostname, port);
    serveRequests(server, handler);
    return DebugService._(
      chromeProxyService,
      server.address.host,
      port,
      authToken,
      serviceExtensionRegistry,
      server,
      useSse,
    );
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
