// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:io';

import 'package:test/test.dart';

import 'fixtures/context.dart';

final context = TestContext();

void main() {
  setUpAll(() async {
    await context.setUp();
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  test('Refuses connections without the auth token', () async {
    expect(
        WebSocket.connect('ws://localhost:${context.debugConnection.port}/ws'),
        throwsA(isA<WebSocketException>()));
  });

  test('Accepts connections with the auth token', () async {
    expect(WebSocket.connect('${context.debugConnection.uri}/ws'), completes);
  });
}
