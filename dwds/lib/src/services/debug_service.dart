// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dds/dds_launcher.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/services/web_socket_proxy_service.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart' hide Response;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _kSseHandlerPath = '\$debugHandler';

bool _acceptNewConnections = true;

final _clientConnections = <int, StreamChannel>{};
int _clientId = 0;

Logger _logger = Logger('DebugService');

void _handleConnection(
  StreamChannel channel,
  ChromeProxyService chromeProxyService,
  ServiceExtensionRegistry serviceExtensionRegistry, {
  void Function(Map<String, Object>)? onRequest,
  void Function(Map<String, Object?>)? onResponse,
}) {
  final clientId = _clientId++;
  final responseController = StreamController<Map<String, Object?>>();
  responseController.stream
      .asyncMap<String>((response) async {
        // This error indicates a successful invocation to _yieldControlToDDS.
        // We don't have a good way to access the list of connected clients
        // while also being able to determine which client invoked the RPC
        // without some form of client ID.
        //
        // We can probably do better than this, but it will likely involve some
        // refactoring.
        if (response case {
          'error': {
            'code': DisconnectNonDartDevelopmentServiceClients.kErrorCode,
          },
        }) {
          final nonDdsClients = _clientConnections.entries
              .where((MapEntry<int, StreamChannel> e) => e.key != clientId)
              .map((e) => e.value);
          await Future.wait([
            for (final client in nonDdsClients) client.sink.close(),
          ]);
          // Remove the artificial error and return Success.
          response.remove('error');
          response['result'] = Success().toJson();
        }
        if (onResponse != null) onResponse(response);
        return jsonEncode(response);
      })
      .listen(channel.sink.add, onError: channel.sink.addError);
  final inputStream = channel.stream.map((value) {
    if (value is List<int>) {
      value = utf8.decode(value);
    } else if (value is! String) {
      throw StateError(
        'Got value with unexpected type ${value.runtimeType} from web '
        'socket, expected a List<int> or String.',
      );
    }
    final request = Map<String, Object>.from(jsonDecode(value));
    if (onRequest != null) onRequest(request);
    return request;
  });
  VmServerConnection(
    inputStream,
    responseController.sink,
    serviceExtensionRegistry,
    chromeProxyService,
  ).done.whenComplete(() {
    _clientConnections.remove(clientId);
    if (!_acceptNewConnections && _clientConnections.isEmpty) {
      // DDS has disconnected so we can allow for clients to connect directly
      // to DWDS.
      ChromeDebugService._ddsUri = null;
      _acceptNewConnections = true;
    }
  });
  _clientConnections[clientId] = channel;
}

void Function(WebSocketChannel, String?) _createNewConnectionHandler(
  ChromeProxyService chromeProxyService,
  ServiceExtensionRegistry serviceExtensionRegistry, {
  void Function(Map<String, Object>)? onRequest,
  void Function(Map<String, Object?>)? onResponse,
}) {
  return (webSocket, subprotocol) {
    _handleConnection(
      webSocket,
      chromeProxyService,
      serviceExtensionRegistry,
      onRequest: onRequest,
      onResponse: onResponse,
    );
  };
}

Future<void> _handleSseConnections(
  SseHandler handler,
  ChromeProxyService chromeProxyService,
  ServiceExtensionRegistry serviceExtensionRegistry, {
  void Function(Map<String, Object>)? onRequest,
  void Function(Map<String, Object?>)? onResponse,
}) async {
  while (await handler.connections.hasNext) {
    final connection = await handler.connections.next;
    _handleConnection(
      connection,
      chromeProxyService,
      serviceExtensionRegistry,
      onRequest: onRequest,
      onResponse: onResponse,
    );
  }
}

/// Common interface for debug services (Chrome or WebSocket based).
abstract class DebugService {
  String get hostname;
  int get port;
  String get uri;
  Future<String> get encodedUri;
  ServiceExtensionRegistry get serviceExtensionRegistry;
  Future<void> close();
}

/// A Dart Web Debug Service.
///
/// Creates a [ChromeProxyService] from an existing Chrome instance.
class ChromeDebugService implements DebugService {
  static String? _ddsUri;

  final ChromeProxyService chromeProxyService;
  @override
  final String hostname;
  @override
  final ServiceExtensionRegistry serviceExtensionRegistry;
  @override
  final int port;
  final String authToken;
  final HttpServer _server;
  final bool _useSse;
  final DartDevelopmentServiceConfiguration _ddsConfig;
  final UrlEncoder? _urlEncoder;
  DartDevelopmentServiceLauncher? _dds;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  ChromeDebugService._(
    this.chromeProxyService,
    this.hostname,
    this.port,
    this.authToken,
    this.serviceExtensionRegistry,
    this._server,
    this._useSse,
    this._ddsConfig,
    this._urlEncoder,
  );

  @override
  Future<void> close() =>
      _closed ??= Future.wait([
        _server.close(),
        if (_dds != null) _dds!.shutdown(),
      ]);

  Future<DartDevelopmentServiceLauncher> startDartDevelopmentService() async {
    // Note: DDS can handle both web socket and SSE connections with no
    // additional configuration.
    _dds = await DartDevelopmentServiceLauncher.start(
      remoteVmServiceUri: Uri(
        scheme: 'http',
        host: hostname,
        port: port,
        path: authToken,
      ),
      serviceUri: Uri(
        scheme: 'http',
        host: hostname,
        port: _ddsConfig.port ?? 0,
      ),
      devToolsServerAddress: _ddsConfig.devToolsServerAddress,
      serveDevTools: _ddsConfig.serveDevTools,
    );
    return _dds!;
  }

  @override
  String get uri {
    final dds = _dds;
    if (_ddsConfig.enable && dds != null) {
      return (_useSse ? dds.sseUri : dds.wsUri).toString();
    }
    return (_useSse
            ? Uri(
              scheme: 'sse',
              host: hostname,
              port: port,
              path: '$authToken/\$debugHandler',
            )
            : Uri(scheme: 'ws', host: hostname, port: port, path: authToken))
        .toString();
  }

  String? _encodedUri;
  @override
  Future<String> get encodedUri async {
    if (_encodedUri != null) return _encodedUri!;
    var encoded = uri;
    if (_urlEncoder != null) encoded = await _urlEncoder(encoded);
    return _encodedUri = encoded;
  }

  static void yieldControlToDDS(String uri) {
    if (_ddsUri != null) {
      // This exception is identical to the one thrown from
      // sdk/lib/vmservice/vmservice.dart
      throw RPCError(
        '_yieldControlToDDS',
        RPCErrorKind.kFeatureDisabled.code,
        'A DDS instance is already connected at $_ddsUri.',
        {'ddsUri': _ddsUri.toString()},
      );
    }
    _acceptNewConnections = false;
    _ddsUri = uri;
  }

  static Future<ChromeDebugService> start(
    String hostname,
    RemoteDebugger remoteDebugger,
    ExecutionContext executionContext,
    AssetReader assetReader,
    AppConnection appConnection,
    UrlEncoder? urlEncoder, {
    void Function(Map<String, Object>)? onRequest,
    void Function(Map<String, Object?>)? onResponse,
    required DartDevelopmentServiceConfiguration ddsConfig,
    bool useSse = false,
    ExpressionCompiler? expressionCompiler,
  }) async {
    final root = assetReader.basePath;
    final chromeProxyService = await ChromeProxyService.create(
      remoteDebugger,
      root,
      assetReader,
      appConnection,
      executionContext,
      expressionCompiler,
    );
    final authToken = _makeAuthToken();
    final serviceExtensionRegistry = ServiceExtensionRegistry();
    Handler handler;
    // DDS will always connect to DWDS via web sockets.
    if (useSse && !ddsConfig.enable) {
      final sseHandler = SseHandler(
        Uri.parse('/$authToken/$_kSseHandlerPath'),
        keepAlive: const Duration(seconds: 5),
      );
      handler = sseHandler.handler;
      safeUnawaited(
        _handleSseConnections(
          sseHandler,
          chromeProxyService,
          serviceExtensionRegistry,
          onRequest: onRequest,
          onResponse: onResponse,
        ),
      );
    } else {
      final innerHandler = webSocketHandler(
        _createNewConnectionHandler(
          chromeProxyService,
          serviceExtensionRegistry,
          onRequest: onRequest,
          onResponse: onResponse,
        ),
      );
      handler = (shelf.Request request) {
        if (!_acceptNewConnections) {
          return shelf.Response.forbidden(
            'Cannot connect directly to the VM service as a Dart Development '
            'Service (DDS) instance has taken control and can be found at '
            '$_ddsUri.',
          );
        }
        if (request.url.pathSegments.first != authToken) {
          return shelf.Response.forbidden('Incorrect auth token');
        }
        return innerHandler(request);
      };
    }
    final server = await startHttpServer(hostname, port: 44456);
    serveHttpRequests(server, handler, (e, s) {
      _logger.warning('Error serving requests', e);
      emitEvent(DwdsEvent.httpRequestException('DebugService', '$e:$s'));
    });
    return ChromeDebugService._(
      chromeProxyService,
      server.address.host,
      server.port,
      authToken,
      serviceExtensionRegistry,
      server,
      useSse,
      ddsConfig,
      urlEncoder,
    );
  }
}

/// Defines callbacks for sending messages to the connected client.
/// Returns the number of clients the request was successfully sent to.
typedef SendClientRequest = int Function(Object request);

/// WebSocket-based debug service for web debugging.
class WebSocketDebugService implements DebugService {
  @override
  final String hostname;
  @override
  final int port;
  final String authToken;
  final HttpServer _server;
  final WebSocketProxyService _webSocketProxyService;
  final ServiceExtensionRegistry _serviceExtensionRegistry;
  final UrlEncoder? _urlEncoder;

  Future<void>? _closed;
  DartDevelopmentServiceLauncher? _dds;
  String? _encodedUri;

  WebSocketDebugService._(
    this.hostname,
    this.port,
    this.authToken,
    this._webSocketProxyService,
    this._serviceExtensionRegistry,
    this._server,
    this._urlEncoder,
  );

  /// Returns the WebSocketProxyService instance.
  WebSocketProxyService get webSocketProxyService => _webSocketProxyService;

  /// Returns the ServiceExtensionRegistry instance.
  @override
  ServiceExtensionRegistry get serviceExtensionRegistry =>
      _serviceExtensionRegistry;

  /// Closes the debug service and associated resources.
  @override
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

  @override
  String get uri =>
      Uri(scheme: 'ws', host: hostname, port: port, path: authToken).toString();

  @override
  Future<String> get encodedUri async {
    if (_encodedUri != null) return _encodedUri!;
    var encoded = uri;
    if (_urlEncoder != null) encoded = await _urlEncoder(encoded);
    return _encodedUri = encoded;
  }

  static Future<WebSocketDebugService> start(
    String hostname,
    AppConnection appConnection, {
    required SendClientRequest sendClientRequest,
    UrlEncoder? urlEncoder,
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

    final server = await startHttpServer(hostname, port: 44456);
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
      urlEncoder,
    );
  }

  /// Creates the WebSocket handler for incoming connections.
  static Handler _createWebSocketHandler(
    ServiceExtensionRegistry serviceExtensionRegistry,
    WebSocketProxyService webSocketProxyService,
  ) {
    return webSocketHandler((WebSocketChannel webSocket, String? subprotocol) {
      final clientId = _clientId++;
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

      _clientConnections[clientId] = webSocket;

      VmServerConnection(
        inputStream,
        responseController.sink,
        serviceExtensionRegistry,
        webSocketProxyService,
      ).done.whenComplete(() {
        _clientConnections.remove(clientId);
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
