// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:dwds/data/data_types.dart';
import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:test/test.dart';

void main() {
  group('ExtensionRequest', () {
    test('serializes and deserializes', () {
      final request = ExtensionRequest(
        id: 1,
        command: 'command',
        commandParams: 'params',
      );
      final json = jsonEncode(request);
      final decoded = ExtensionRequest.fromJson(jsonDecode(json) as List);
      expect(decoded, request);
    });
  });

  group('ExtensionResponse', () {
    test('serializes and deserializes', () {
      final response = ExtensionResponse(
        id: 1,
        success: true,
        result: 'result',
        error: 'error',
      );
      final json = jsonEncode(response);
      final decoded = ExtensionResponse.fromJson(jsonDecode(json) as List);
      expect(decoded, response);
    });
  });

  group('ExtensionEvent', () {
    test('serializes and deserializes', () {
      final event = ExtensionEvent(method: 'method', params: 'params');
      final json = jsonEncode(event);
      final decoded = ExtensionEvent.fromJson(jsonDecode(json) as List);
      expect(decoded, event);
    });
  });

  group('BatchedEvents', () {
    test('serializes and deserializes', () {
      final event = ExtensionEvent(method: 'method', params: 'params');
      final batch = BatchedEvents(events: [event]);
      final json = jsonEncode(batch);
      final decoded = BatchedEvents.fromJson(jsonDecode(json) as List);
      expect(decoded, batch);
    });
  });

  group('DevToolsRequest', () {
    test('serializes and deserializes', () {
      final request = DevToolsRequest(
        appId: 'appId',
        instanceId: 'instanceId',
        contextId: 1,
        tabUrl: 'tabUrl',
        uriOnly: true,
        client: 'client',
      );
      final json = jsonEncode(request);
      final decoded = DevToolsRequest.fromJson(jsonDecode(json) as List);
      expect(decoded, request);
    });
  });

  group('DevToolsResponse', () {
    test('serializes and deserializes', () {
      final response = DevToolsResponse(
        success: true,
        promptExtension: true,
        error: 'error',
      );
      final json = jsonEncode(response);
      final decoded = DevToolsResponse.fromJson(jsonDecode(json) as List);
      expect(decoded, response);
    });
  });

  group('ConnectFailure', () {
    test('serializes and deserializes', () {
      final failure = ConnectFailure(tabId: 1, reason: 'reason');
      final json = jsonEncode(failure);
      final decoded = ConnectFailure.fromJson(jsonDecode(json) as List);
      expect(decoded, failure);
    });
  });

  group('DevToolsOpener', () {
    test('serializes and deserializes', () {
      final opener = DevToolsOpener(newWindow: true);
      final json = jsonEncode(opener);
      final decoded = DevToolsOpener.fromJson(jsonDecode(json) as List);
      expect(decoded, opener);
    });
  });

  group('DevToolsUrl', () {
    test('serializes and deserializes', () {
      final url = DevToolsUrl(tabId: 1, url: 'url');
      final json = jsonEncode(url);
      final decoded = DevToolsUrl.fromJson(jsonDecode(json) as List);
      expect(decoded, url);
    });
  });

  group('DebugStateChange', () {
    test('serializes and deserializes', () {
      final change = DebugStateChange(
        tabId: 1,
        newState: 'newState',
        reason: 'reason',
      );
      final json = jsonEncode(change);
      final decoded = DebugStateChange.fromJson(jsonDecode(json) as List);
      expect(decoded, change);
    });
  });

  group('DebugInfo', () {
    test('serializes and deserializes', () {
      final info = DebugInfo(
        appEntrypointPath: 'appEntrypointPath',
        appId: 'appId',
        appInstanceId: 'appInstanceId',
        appOrigin: 'appOrigin',
        appUrl: 'appUrl',
        authUrl: 'authUrl',
        dwdsVersion: 'dwdsVersion',
        extensionUrl: 'extensionUrl',
        isInternalBuild: true,
        isFlutterApp: true,
        workspaceName: 'workspaceName',
        tabUrl: 'tabUrl',
        tabId: 1,
      );
      final json = jsonEncode(info);
      final decoded = DebugInfo.fromJson(jsonDecode(json) as List);
      expect(decoded, info);
    });
  });
}
