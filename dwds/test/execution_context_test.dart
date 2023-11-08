// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
import 'dart:async';
import 'dart:convert';

import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/servers/extension_debugger.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';

import 'fixtures/fakes.dart';

void main() async {
  final bool debug = false;

  group('ExecutionContext', () {
    setUpAll(() {
      setCurrentLogWriter(debug: debug);
    });

    TestDebuggerConnection? debugger;
    TestDebuggerConnection getDebugger() => debugger!;

    setUp(() async {
      setCurrentLogWriter(debug: debug);
      debugger = TestDebuggerConnection();
    });

    tearDown(() async {
      await debugger?.close();
    });

    test('is created on devtools request', () async {
      final debugger = getDebugger();
      await debugger.createDebuggerExecutionContext(contextId: 1);

      // Expect the context ID to be set.
      expect(await debugger.getDefaultContextId(), 1);
    });

    test('clears context ID', () async {
      final debugger = getDebugger();
      await debugger.createDebuggerExecutionContext(contextId: 1);

      debugger.sendContextsClearedEvent();

      // Expect non-dart context.
      expect(await debugger.getDefaultContextId(), isNull);
    });

    test('finds dart context ID', () async {
      final debugger = getDebugger();

      await debugger.createDebuggerExecutionContext(contextId: null);
      debugger.sendContextCreatedEvent(2);

      // Expect dart context.
      expect(await debugger.getContextId(isDart: true), 2);
    });

    test('does not find dart context ID if not available', () async {
      final debugger = getDebugger();

      await debugger.createDebuggerExecutionContext(contextId: null);

      // No context IDs received yet.
      expect(await debugger.getDefaultContextId(), null);

      // Send 'context created' event
      final contextId = 2;
      debugger.sendContextCreatedEvent(contextId);

      // Expect non-dart context
      // This mocks injected client still loading.
      expect(await debugger.getContextId(isDart: false), null);

      // Expect dart context.
      // This mocks injected client loading later for previously
      // received context ID.
      expect(await debugger.getContextId(isDart: true), contextId);
    });
  });
}

class TestDebuggerConnection {
  late final ExtensionDebugger extensionDebugger;
  late final FakeSseConnection connection;

  int _evaluateRequestId = 0;

  TestDebuggerConnection() {
    connection = FakeSseConnection();
    extensionDebugger = ExtensionDebugger(connection);
  }

  /// Create a new execution context in the debugger.
  Future<void> createDebuggerExecutionContext({int? contextId}) {
    _sendDevToolsRequest(contextId: contextId);
    return _executionContext();
  }

  /// Flush the streams and close debugger connection.
  Future<void> close() async {
    unawaited(connection.controllerOutgoing.stream.any((e) => false));
    unawaited(extensionDebugger.devToolsRequestStream.any((e) => false));

    await connection.controllerIncoming.sink.close();
    await connection.controllerOutgoing.sink.close();

    await extensionDebugger.close();
  }

  /// Return the initial context ID from the DevToolsRequest.
  Future<int?> getDefaultContextId() async {
    // Give the previous events time to propagate.
    await Future.delayed(Duration(milliseconds: 100));
    return await extensionDebugger.executionContext!.id;
  }

  /// Mock receiving context IDs in the execution context.
  ///
  /// [isDart] will cause a dart context to be created.
  ///
  /// Dart context is detected by evaluation of
  /// `window.$dartAppInstanceId` in that context returning
  /// a non-null value.
  Future<int?> getContextId({bool isDart = false}) async {
    // Try getting execution id.
    final executionContextId = extensionDebugger.executionContext!.id;

    // Give it time to send the evaluate request.
    await Future.delayed(Duration(milliseconds: 100));

    // Respond to the evaluate request
    final extensionResponse = ExtensionResponse(
      (b) => b
        ..result = jsonEncode({
          'result': {'value': isDart ? 'dart' : null},
        })
        ..id = _evaluateRequestId++
        ..success = true,
    );
    connection.controllerIncoming.sink
        .add(jsonEncode(serializers.serialize(extensionResponse)));

    return await executionContextId;
  }

  /// Send `Runtime.executionContextsCleared` event to the execution
  /// context in the extension debugger.
  void sendContextsClearedEvent() {
    final extensionEvent = ExtensionEvent(
      (b) => b
        ..method = jsonEncode('Runtime.executionContextsCleared')
        ..params = jsonEncode({}),
    );
    connection.controllerIncoming.sink
        .add(jsonEncode(serializers.serialize(extensionEvent)));
  }

  /// Send `Runtime.executionContextCreated` event to the execution
  /// context in the extension debugger.
  void sendContextCreatedEvent(int contextId) {
    final extensionEvent = ExtensionEvent(
      (b) => b
        ..method = jsonEncode('Runtime.executionContextCreated')
        ..params = jsonEncode({
          "context": {"id": "$contextId"},
        }),
    );
    connection.controllerIncoming.sink
        .add(jsonEncode(serializers.serialize(extensionEvent)));
  }

  void _sendDevToolsRequest({int? contextId}) {
    final devToolsRequest = DevToolsRequest(
      (b) => b
        ..contextId = contextId
        ..appId = 'app'
        ..instanceId = '0',
    );
    connection.controllerIncoming.sink
        .add(jsonEncode(serializers.serialize(devToolsRequest)));
  }

  Future<void> _executionContext() async {
    final executionContext = await _waitForExecutionContext().timeout(
      const Duration(milliseconds: 100),
      onTimeout: () {
        expect(fail, 'Timeout getting execution context');
        return null;
      },
    );
    expect(executionContext, isNotNull);
  }

  Future<ExecutionContext?> _waitForExecutionContext() async {
    while (extensionDebugger.executionContext == null) {
      await Future.delayed(Duration(milliseconds: 20));
    }
    return extensionDebugger.executionContext;
  }
}
