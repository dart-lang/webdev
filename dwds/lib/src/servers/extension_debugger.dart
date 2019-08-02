// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// A debugger backed by the Dart Debug Extension.
class ExtensionDebugger implements WipDebugger {
  /// A connection between the debugger and the background of
  /// Dart Debug Extension
  final SseConnection sseConnection;

  /// A map from id to a completer associated with an [ExtensionRequest]
  final _completers = <int, Completer>{};
  final _eventStreams = <String, Stream>{};
  var _completerId = 0;

  @override
  WipConnection get connection => throw UnimplementedError();

  String tabUrl;
  String appId;
  String instanceId;

  final _devToolsRequestController = StreamController<DevToolsRequest>();
  Stream<DevToolsRequest> get devToolsRequestStream =>
      _devToolsRequestController.stream;

  final _notificationController = StreamController<WipEvent>.broadcast();
  Stream<WipEvent> get onNotification => _notificationController.stream;

  Stream<ConsoleAPIEvent> get onConsoleAPICalled => eventStream(
      'Runtime.consoleAPICalled', (WipEvent event) => ConsoleAPIEvent(event));

  Stream<ExceptionThrownEvent> get onExceptionThrown => eventStream(
      'Runtime.exceptionThrown',
      (WipEvent event) => ExceptionThrownEvent(event));

  ExtensionDebugger(this.sseConnection) {
    sseConnection.stream.listen((data) {
      var message = serializers.deserialize(jsonDecode(data));
      if (message is ExtensionResponse) {
        var encodedResult = {
          'result': json.decode(message.result),
          'id': message.id
        };
        if (_completers[message.id] == null) {
          throw StateError('Missing completer.');
        }
        _completers[message.id].complete(WipResponse(encodedResult));
      } else if (message is ExtensionEvent) {
        var map = {
          'method': json.decode(message.method),
          'params': json.decode(message.params)
        };
        _notificationController.sink.add(WipEvent(map));
      } else if (message is DevToolsRequest) {
        tabUrl = message.tabUrl;
        appId = message.appId;
        instanceId = message.instanceId;
        _devToolsRequestController.sink.add(message);
      }
    }, onError: (_) {
      close();
    });
  }

  /// Sends a [command] with optional [params] to Dart Debug Extension
  /// over the SSE connection.
  @override
  Future<WipResponse> sendCommand(String command,
      {Map<String, dynamic> params}) {
    var completer = Completer<WipResponse>();
    var id = newId();
    _completers[id] = completer;
    sseConnection.sink.add(jsonEncode(serializers.serialize(ExtensionRequest(
        (b) => b
          ..id = id
          ..command = command
          ..commandParams =
              BuiltMap<String, Object>(params ?? {}).toBuilder()))));
    return completer.future;
  }

  int newId() => _completerId++;

  Future<void> close() => sseConnection.sink.close();

  @override
  Future disable() => sendCommand('Debugger.disable');

  @override
  Future enable() => sendCommand('Debugger.enable');

  @override
  Future<String> getScriptSource(String scriptId) async =>
      (await sendCommand('Debugger.getScriptSource',
              params: {'scriptId': scriptId}))
          .result['scriptSource'] as String;

  @override
  Future<WipResponse> pause() => sendCommand('Debugger.pause');

  @override
  Future<WipResponse> resume() => sendCommand('Debugger.resume');

  @override
  Future<WipResponse> setPauseOnExceptions(PauseState state) =>
      sendCommand('Debugger.setPauseOnExceptions',
          params: {'state': _pauseStateToString(state)});

  @override
  Future<WipResponse> stepInto() => sendCommand('Debugger.stepInto');

  @override
  Future<WipResponse> stepOut() => sendCommand('Debugger.stepOut');

  @override
  Future<WipResponse> stepOver() => sendCommand('Debugger.stepOver');

  @override
  Stream<T> eventStream<T>(String method, WipEventTransformer<T> transformer) {
    return _eventStreams
        .putIfAbsent(
            method,
            () => onNotification
                .where((event) => event.method == method)
                .map(transformer)
            // () => StreamTransformer.fromHandlers(
            //   handleData: (WipEvent event, EventSink<T> sink) {
            //     if (event.method == method) {
            //       sink.add(transformer(event));
            //     }
            //   },
            // ).bind(onNotification),
            )
        .cast();
  }

  @override
  Stream<WipDomain> get onClosed => throw UnimplementedError();

  @override
  Stream<GlobalObjectClearedEvent> get onGlobalObjectCleared => eventStream(
      'Debugger.globalObjectCleared',
      (WipEvent event) => GlobalObjectClearedEvent(event));

  @override
  Stream<DebuggerPausedEvent> get onPaused => eventStream(
      'Debugger.paused', (WipEvent event) => DebuggerPausedEvent(event));

  @override
  Stream<DebuggerResumedEvent> get onResumed => eventStream(
      'Debugger.resumed', (WipEvent event) => DebuggerResumedEvent(event));
  @override
  Stream<ScriptParsedEvent> get onScriptParsed => eventStream(
      'Debugger.scriptParsed', (WipEvent event) => ScriptParsedEvent(event));

  @override
  Map<String, WipScript> get scripts => throw UnimplementedError();

  String _pauseStateToString(PauseState state) {
    switch (state) {
      case PauseState.all:
        return 'all';
      case PauseState.none:
        return 'none';
      case PauseState.uncaught:
        return 'uncaught';
      default:
        throw ArgumentError('unknown state: $state');
    }
  }
}
