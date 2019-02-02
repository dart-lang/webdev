// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/serializers.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:webdev/src/serve/handlers/build_results_handler.dart';

const _pumpTimes = 150;

void main() {
  StreamController<BuildResult> streamController;
  HttpServer server;

  group('BuildResultsHandler', () {
    setUp(() async {
      streamController = StreamController<BuildResult>();
      var handler = BuildResultsHandler(streamController.stream);
      server = await shelf_io.serve(handler.handler, 'localhost', 0);
    });

    tearDown(() async {
      await server.close();
    });
    test('updates a single client', () async {
      var client = await WebSocket.connect('ws://localhost:${server.port}',
          protocols: [r'$buildResults']);
      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));
      var event = await client.first;
      var result =
          serializers.deserialize(jsonDecode(event as String)) as BuildResult;
      expect(result.status, BuildStatus.succeeded);
    });

    test('updates multiple clients', () async {
      var clientA = await WebSocket.connect('ws://localhost:${server.port}',
          protocols: [r'$buildResults']);
      var clientB = await WebSocket.connect('ws://localhost:${server.port}',
          protocols: [r'$buildResults']);
      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));
      var eventA = await clientA.first;
      var resultA =
          serializers.deserialize(jsonDecode(eventA as String)) as BuildResult;
      var eventB = await clientB.first;
      var resultB =
          serializers.deserialize(jsonDecode(eventB as String)) as BuildResult;

      expect(resultA.status, BuildStatus.succeeded);
      expect(resultB.status, BuildStatus.succeeded);
    });

    test('does not update disconnected clients', () async {
      var client = await WebSocket.connect('ws://localhost:${server.port}',
          protocols: [r'$buildResults']);

      var events = 0;
      client.listen((_) {
        events++;
      });

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));
      await pumpEventQueue(times: _pumpTimes);

      await client.close();
      await pumpEventQueue();

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));
      await pumpEventQueue();

      expect(events, 1);
    });

    test('updates non disconnected clients', () async {
      var clientA = await WebSocket.connect('ws://localhost:${server.port}',
          protocols: [r'$buildResults']);
      var clientB = await WebSocket.connect('ws://localhost:${server.port}',
          protocols: [r'$buildResults']);

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));

      var events = 0;
      clientA.listen((_) {
        events++;
      });

      await clientB.first;
      await clientB.close();
      await pumpEventQueue(times: _pumpTimes);

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));
      await pumpEventQueue(times: _pumpTimes);

      expect(events, 2);
    });

    test('only forwards success results', () async {
      var client = await WebSocket.connect('ws://localhost:${server.port}',
          protocols: [r'$buildResults']);

      var events = 0;
      client.listen((_) {
        events++;
      });

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));
      await pumpEventQueue(times: _pumpTimes);

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.started));
      await pumpEventQueue(times: _pumpTimes);

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.failed));
      await pumpEventQueue(times: _pumpTimes);

      streamController.add(DefaultBuildResult((b) => b
        ..target = 'foo'
        ..status = BuildStatus.succeeded));
      await pumpEventQueue(times: _pumpTimes);

      expect(events, 2);
    });
  });
}
