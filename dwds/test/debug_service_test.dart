// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dwds/src/services/debug_service.dart';
import 'package:test/test.dart';

import 'test_context.dart';

final context = TestContext();
DebugService get debugService => context.debugService;

void main() {
  setUpAll(() async {
    await context.setUp();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  test('Refuses connections without the auth token', () async {
    expect(
        WebSocket.connect(
            'ws://${debugService.hostname}:${debugService.port}/ws'),
        throwsA(isA<WebSocketException>()));
  });

  test('Accepts connections with the auth token', () async {
    expect(WebSocket.connect('${debugService.wsUri}/ws'), completes);
  });
}
