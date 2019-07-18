// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/servers/extension_debugger.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

import 'fixtures/fakes.dart';

FakeSseConnection connection;
ExtensionDebugger extensionDebugger;

void main() async {
  setUp(() async {
    connection = FakeSseConnection();
    extensionDebugger = ExtensionDebugger(connection);
  });

  test('can send a command & receive a response', () async {
    var extensionResponse = ExtensionResponse((b) => b
      ..result = jsonEncode({
        'result': {'value': 3.14}
      })
      ..id = 0
      ..success = true);
    var resultCompleter = Completer();
    unawaited(extensionDebugger.sendCommand('Runtime.evaluate',
        params: {'expression': '\$pi'}).then((response) {
      resultCompleter.complete(response);
    }));
    connection.controller
        .add(jsonEncode(serializers.serialize(extensionResponse)));
    var response = await resultCompleter.future;
    expect(response.result['value'], 3.14);
  });
}
