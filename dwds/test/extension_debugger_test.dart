// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/servers/extension_debugger.dart';
import 'package:pedantic/pedantic.dart';
import 'package:test/test.dart';

import 'fixtures/debugger_data.dart';
import 'fixtures/fakes.dart';

FakeSseConnection connection;
ExtensionDebugger extensionDebugger;

void main() async {
  setUp(() async {
    connection = FakeSseConnection();
    extensionDebugger = ExtensionDebugger(connection);
  });

  group('can receive', () {
    test('an ExtensionResponse', () async {
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
      connection.controllerIncoming.sink
          .add(jsonEncode(serializers.serialize(extensionResponse)));
      var response = await resultCompleter.future;
      expect(response.result['result']['value'], 3.14);
    });

    test('an ExtensionEvent', () async {
      var extensionEvent = ExtensionEvent((b) => b
        ..method = jsonEncode('Debugger.paused')
        ..params = jsonEncode(frames1[0]));
      connection.controllerIncoming.sink
          .add(jsonEncode(serializers.serialize(extensionEvent)));
      var wipEvent = await extensionDebugger.onNotification.first;
      expect(wipEvent.method, 'Debugger.paused');
      expect(wipEvent.params, frames1[0]);
    });

    test('a DevToolsRequest', () async {
      var devToolsRequest = DevToolsRequest((b) => b
        ..tabUrl = 'pi/calculus'
        ..appId = '3.14'
        ..instanceId = '6.28');
      connection.controllerIncoming.sink
          .add(jsonEncode(serializers.serialize(devToolsRequest)));
      var request = await extensionDebugger.devToolsRequestStream.first;
      expect(request.tabUrl, 'pi/calculus');
      expect(request.appId, '3.14');
      expect(request.instanceId, '6.28');
    });
  });

  test('can send a request', () async {
    var extensionRequest = ExtensionRequest((b) => b
      ..id = 0
      ..command = 'Debugger.pause'
      ..commandParams = jsonEncode({}));
    unawaited(extensionDebugger.pause());
    var request = serializers.deserialize(
        jsonDecode(await connection.controllerOutgoing.stream.first));
    expect(request, extensionRequest);
  });
}
