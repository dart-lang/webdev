// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart' hide Response;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _kSseHandlerPath = '\$debugHandler';

bool _acceptNewConnections = true;
int _clientsConnected = 0;

Logger _logger = Logger('DebugService');

void Function(WebSocketChannel) _createNewConnectionHandler(
  ChromeProxyService chromeProxyService,
  ServiceExtensionRegistry serviceExtensionRegistry, {
  void Function(Map<String, Object>)? onRequest,
  void Function(Map<String, Object?>)? onResponse,
}) {
  return (webSocket) {
    final responseController = StreamController<Map<String, Object?>>();
    webSocket.sink.addStream(
      responseController.stream.map((response) {
        if (onResponse != null) onResponse(response);
        return jsonEncode(response);
      }),
    );
    final inputStream = webSocket.stream.map((value) {
      if (value is List<int>) {
        value = utf8.decode(value);
      } else if (value is! String) {
        throw StateError(
            'Got value with unexpected type ${value.runtimeType} from web '
            'socket, expected a List<int> or String.');
      }
      final request = Map<String, Object>.from(jsonDecode(value));
      if (onRequest != null) onRequest(request);
      return request;
    });
    ++_clientsConnected;
    VmServerConnection(
      inputStream,
      responseController.sink,
      serviceExtensionRegistry,
      chromeProxyService,
    ).done.whenComplete(() {
      --_clientsConnected;
      if (!_acceptNewConnections && _clientsConnected == 0) {
        // DDS has disconnected so we can allow for clients to connect directly
        // to DWDS.
        _acceptNewConnections = true;
      }
    });
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
    final responseController = StreamController<Map<String, Object?>>();
    final sub = responseController.stream.map((response) {
      if (onResponse != null) onResponse(response);
      return jsonEncode(response);
    }).listen(connection.sink.add);
    safeUnawaited(
      chromeProxyService.remoteDebugger.onClose.first.whenComplete(() {
        connection.sink.close();
        sub.cancel();
      }),
    );
    final inputStream = connection.stream.map((value) {
      final request = jsonDecode(value) as Map<String, Object>;
      if (onRequest != null) onRequest(request);
      return request;
    });
    ++_clientsConnected;
    final vmServerConnection = VmServerConnection(
      inputStream,
      responseController.sink,
      serviceExtensionRegistry,
      chromeProxyService,
    );
    safeUnawaited(
      vmServerConnection.done.whenComplete(() {
        --_clientsConnected;
        if (!_acceptNewConnections && _clientsConnected == 0) {
          // DDS has disconnected so we can allow for clients to connect directly
          // to DWDS.
          _acceptNewConnections = true;
        }
        return sub.cancel();
      }),
    );
  }
}

/// Wrapper around a `dart development-service` process.
class DartDevelopmentService {
  static Future<DartDevelopmentService> start({
    required Uri remoteVmServiceUri,
    required Uri serviceUri,
  }) async {
    final process = await Process.start(
      Platform.executable,
      <String>[
        'development-service',
        '--vm-service-uri=$remoteVmServiceUri',
        '--bind-address=${serviceUri.host}',
        '--bind-port=${serviceUri.port}',
      ],
    );
    final completer = Completer<DartDevelopmentService>();
    late StreamSubscription<Object?> stderrSub;
    stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(json.decoder)
        .listen((Object? result) {
      if (result
          case {
            'state': 'started',
            'ddsUri': final String ddsUriStr,
          }) {
        final ddsUri = Uri.parse(ddsUriStr);
        completer.complete(
          DartDevelopmentService._(
            process: process,
            uri: ddsUri,
          ),
        );
      } else if (result
          case {
            'state': 'error',
            'error': final String error,
          }) {
        final exceptionDetails =
            result['ddsExceptionDetails'] as Map<String, Object?>?;
        completer.completeError(
          exceptionDetails != null
              ? DartDevelopmentServiceException.fromJson(exceptionDetails)
              : StateError(error),
        );
      } else {
        throw StateError('Unexpected result from DDS: $result');
      }
      stderrSub.cancel();
    });
    return completer.future;
  }

  DartDevelopmentService._({
    required Process process,
    required this.uri,
  }) : _ddsInstance = process;

  final Process _ddsInstance;

  final Uri uri;

  Uri get sseUri => _toSse(uri)!;
  Uri get wsUri => _toWebSocket(uri)!;

  List<String> _cleanupPathSegments(Uri uri) {
    final pathSegments = <String>[];
    if (uri.pathSegments.isNotEmpty) {
      pathSegments.addAll(
        uri.pathSegments.where(
          // Strip out the empty string that appears at the end of path segments.
          // Empty string elements will result in an extra '/' being added to the
          // URI.
          (s) => s.isNotEmpty,
        ),
      );
    }
    return pathSegments;
  }

  Uri? _toWebSocket(Uri? uri) {
    if (uri == null) {
      return null;
    }
    final pathSegments = _cleanupPathSegments(uri);
    pathSegments.add('ws');
    return uri.replace(scheme: 'ws', pathSegments: pathSegments);
  }

  Uri? _toSse(Uri? uri) {
    if (uri == null) {
      return null;
    }
    final pathSegments = _cleanupPathSegments(uri);
    pathSegments.add(_kSseHandlerPath);
    return uri.replace(scheme: 'sse', pathSegments: pathSegments);
  }

  Future<void> shutdown() {
    _ddsInstance.kill();
    return _ddsInstance.exitCode;
  }
}

/// Thrown by DDS during initialization failures, unexpected connection issues,
/// and when attempting to spawn DDS when an existing DDS instance exists.
class DartDevelopmentServiceException implements Exception {
  factory DartDevelopmentServiceException.fromJson(Map<String, Object?> json) {
    if (json
        case {
          'error_code': final int errorCode,
          'message': final String message,
          'uri': final String? uri
        }) {
      return switch (errorCode) {
        existingDdsInstanceError =>
          DartDevelopmentServiceException.existingDdsInstance(
            message,
            ddsUri: Uri.parse(uri!),
          ),
        failedToStartError => DartDevelopmentServiceException.failedToStart(),
        connectionError =>
          DartDevelopmentServiceException.connectionIssue(message),
        _ => throw StateError(
            'Invalid DartDevelopmentServiceException error_code: $errorCode',
          ),
      };
    }
    throw StateError('Invalid DartDevelopmentServiceException JSON: $json');
  }

  /// Thrown when `DartDeveloperService.startDartDevelopmentService` is called
  /// and the target VM service already has a Dart Developer Service instance
  /// connected.
  factory DartDevelopmentServiceException.existingDdsInstance(
    String message, {
    Uri? ddsUri,
  }) {
    return ExistingDartDevelopmentServiceException._(
      message,
      ddsUri: ddsUri,
    );
  }

  /// Thrown when the connection to the remote VM service terminates unexpectedly
  /// during Dart Development Service startup.
  factory DartDevelopmentServiceException.failedToStart() {
    return DartDevelopmentServiceException._(
      failedToStartError,
      'Failed to start Dart Development Service',
    );
  }

  /// Thrown when a connection error has occurred after startup.
  factory DartDevelopmentServiceException.connectionIssue(String message) {
    return DartDevelopmentServiceException._(connectionError, message);
  }

  DartDevelopmentServiceException._(this.errorCode, this.message);

  /// Set when `DartDeveloperService.startDartDevelopmentService` is called and
  /// the target VM service already has a Dart Developer Service instance
  /// connected.
  static const int existingDdsInstanceError = 1;

  /// Set when the connection to the remote VM service terminates unexpectedly
  /// during Dart Development Service startup.
  static const int failedToStartError = 2;

  /// Set when a connection error has occurred after startup.
  static const int connectionError = 3;

  @override
  String toString() => 'DartDevelopmentServiceException: $message';

  final int errorCode;
  final String message;
}

/// Thrown when attempting to start a new DDS instance when one already exists.
class ExistingDartDevelopmentServiceException
    extends DartDevelopmentServiceException {
  ExistingDartDevelopmentServiceException._(
    String message, {
    this.ddsUri,
  }) : super._(
          DartDevelopmentServiceException.existingDdsInstanceError,
          message,
        );

  /// The URI of the existing DDS instance, if available.
  ///
  /// This URI is the base HTTP URI such as `http://127.0.0.1:1234/AbcDefg=/`,
  /// not the WebSocket URI (which can be obtained by mapping the scheme to
  /// `ws` (or `wss`) and appending `ws` to the path segments).
  final Uri? ddsUri;
}

/// A Dart Web Debug Service.
///
/// Creates a [ChromeProxyService] from an existing Chrome instance.
class DebugService {
  static String? _ddsUri;

  final VmServiceInterface chromeProxyService;
  final String hostname;
  final ServiceExtensionRegistry serviceExtensionRegistry;
  final int port;
  final String authToken;
  final HttpServer _server;
  final bool _useSse;
  final bool _spawnDds;
  final UrlEncoder? _urlEncoder;
  DartDevelopmentService? _dds;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  DebugService._(
    this.chromeProxyService,
    this.hostname,
    this.port,
    this.authToken,
    this.serviceExtensionRegistry,
    this._server,
    this._useSse,
    this._spawnDds,
    this._urlEncoder,
  );

  Future<void> close() => _closed ??= Future.wait([
        _server.close(),
        if (_dds != null) _dds!.shutdown(),
      ]);

  Future<DartDevelopmentService> startDartDevelopmentService() async {
    // Note: DDS can handle both web socket and SSE connections with no
    // additional configuration.
    _dds = await DartDevelopmentService.start(
      remoteVmServiceUri: Uri(
        scheme: 'http',
        host: hostname,
        port: port,
        path: authToken,
      ),
      serviceUri: Uri(
        scheme: 'http',
        host: hostname,
        port: 0,
      ),
    );
    return _dds!;
  }

  String get uri {
    final dds = _dds;
    if (_spawnDds && dds != null) {
      return (_useSse ? dds.sseUri : dds.wsUri).toString();
    }
    return (_useSse
            ? Uri(
                scheme: 'sse',
                host: hostname,
                port: port,
                path: '$authToken/\$debugHandler',
              )
            : Uri(
                scheme: 'ws',
                host: hostname,
                port: port,
                path: authToken,
              ))
        .toString();
  }

  String? _encodedUri;
  Future<String> get encodedUri async {
    if (_encodedUri != null) return _encodedUri!;
    var encoded = uri;
    if (_urlEncoder != null) encoded = await _urlEncoder(encoded);
    return _encodedUri = encoded;
  }

  // TODO(https://github.com/dart-lang/webdev/issues/2399): yieldControlToDDS
  // should disconnect existing non-DDS clients.
  static bool yieldControlToDDS(String uri) {
    if (_clientsConnected > 1) {
      return false;
    }
    _ddsUri = uri;
    _acceptNewConnections = false;
    return true;
  }

  static Future<DebugService> start(
    String hostname,
    RemoteDebugger remoteDebugger,
    ExecutionContext executionContext,
    AssetReader assetReader,
    AppConnection appConnection,
    UrlEncoder? urlEncoder, {
    void Function(Map<String, Object>)? onRequest,
    void Function(Map<String, Object?>)? onResponse,
    bool spawnDds = true,
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
    if (useSse && !spawnDds) {
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
    return DebugService._(
      chromeProxyService,
      server.address.host,
      server.port,
      authToken,
      serviceExtensionRegistry,
      server,
      useSse,
      spawnDds,
      urlEncoder,
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
