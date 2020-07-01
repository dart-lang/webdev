import 'dart:async';

import 'package:async/async.dart';
import 'package:pedantic/pedantic.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class SocketConnection {
  bool get isInKeepAlivePeriod;
  StreamSink<dynamic> get sink;
  Stream<String> get stream;
  void shutdown();
}

abstract class SocketHandler {
  StreamQueue<SocketConnection> get connections;
  FutureOr<Response> handler(Request request);
  void shutdown();
}

class SseSocketConnection extends SocketConnection {
  final SseConnection _connection;

  SseSocketConnection(this._connection);

  @override
  bool get isInKeepAlivePeriod => _connection.isInKeepAlivePeriod;
  @override
  StreamSink<dynamic> get sink => _connection.sink;
  @override
  Stream<String> get stream => _connection.stream;
  @override
  void shutdown() => _connection.shutdown();
}

class SseSocketHandler extends SocketHandler {
  final SseHandler _sseHandler;
  final StreamController<SseSocketConnection> _connectionsStream =
      StreamController<SseSocketConnection>();
  StreamQueue<SseSocketConnection> _connectionsStreamQueue;

  SseSocketHandler(this._sseHandler) {
    unawaited(() async {
      var injectedConnections = _sseHandler.connections;
      while (await injectedConnections.hasNext) {
        _connectionsStream
            .add(SseSocketConnection(await injectedConnections.next));
      }
    }());
  }

  @override
  StreamQueue<SseSocketConnection> get connections =>
      _connectionsStreamQueue ??= StreamQueue(_connectionsStream.stream);
  @override
  FutureOr<Response> handler(Request request) => _sseHandler.handler(request);
  @override
  void shutdown() => _sseHandler.shutdown();
}

class WebSocketConnection extends SocketConnection {
  final WebSocketChannel _channel;
  WebSocketConnection(this._channel);

  @override
  bool get isInKeepAlivePeriod => false;
  @override
  StreamSink<dynamic> get sink => _channel.sink;
  @override
  Stream<String> get stream =>
      _channel.stream.map((dynamic o) => o?.toString());
  @override
  void shutdown() => _channel.sink.close();
}

class WebSocketSocketHandler extends SocketHandler {
  Handler _handler;
  final StreamController<WebSocketConnection> _connectionsStream =
      StreamController<WebSocketConnection>();
  StreamQueue<WebSocketConnection> _connectionsStreamQueue;

  WebSocketSocketHandler() {
    _handler = webSocketHandler((WebSocketChannel channel) =>
        _connectionsStream.add(WebSocketConnection(channel)));
  }

  @override
  StreamQueue<WebSocketConnection> get connections =>
      _connectionsStreamQueue ??= StreamQueue(_connectionsStream.stream);
  @override
  FutureOr<Response> handler(Request request) => _handler(request);
  @override
  void shutdown() => throw UnimplementedError();
}
