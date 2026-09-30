// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/src/sockets.dart';
import 'package:test/test.dart';

void main() {
  group('PersistentWebSocket', () {
    late HttpServer server;
    late Uri uri;

    /// Server-side sockets, in order of connection.
    late StreamController<WebSocket> serverSockets;

    setUp(() async {
      serverSockets = StreamController<WebSocket>();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.transform(WebSocketTransformer()).listen(serverSockets.add);
      uri = Uri.parse('ws://${server.address.host}:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
      await serverSockets.close();
    });

    test('closes its sink when the server closes the connection', () async {
      final client = await PersistentWebSocket.connect(uri);
      final serverSocket = await serverSockets.stream.first;
      client.stream.listen(null);

      await serverSocket.close(WebSocketStatus.normalClosure);
      await client.done;

      // Writes after the connection is gone must fail synchronously so that
      // callers can handle them, instead of throwing asynchronously.
      expect(() => client.sink.add('message'), throwsStateError);
    });

    test('drops messages queued before the connection was closed', () async {
      final client = await PersistentWebSocket.connect(uri);
      final serverSocket = await serverSockets.stream.first;
      final received = <Object?>[];
      serverSocket.listen(received.add);

      await serverSocket.close(WebSocketStatus.normalClosure);
      // Give the client time to observe the close.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Queue a message while the underlying socket is closed. It is only
      // written once the client starts listening. This must not result in an
      // unhandled `WebSocketConnectionClosed` error (which would fail this
      // test).
      client.sink.add('message');
      client.stream.listen(null);
      await client.done;

      expect(received, isEmpty);
      expect(() => client.sink.add('message'), throwsStateError);
    });
  });
}
