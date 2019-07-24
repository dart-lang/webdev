// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../data/serializers.dart';

/// A debugger backed by the Dart Debug Extension.
class ExtensionDebugger implements WipDebugger {
  @override
  WipConnection get connection => throw UnimplementedError();

  /// A connection between the debugger and the background of
  /// Dart Debug Extension
  final SseConnection _connection;

  /// A map from id to a completer associated with an [ExtensionRequest]
  final _completers = <int, Completer>{};

  var _completerId = 0;

  ExtensionDebugger(this._connection) {
    _connection.stream.listen((data) {
      var message = serializers.deserialize(jsonDecode(data));
      if (message is ExtensionResponse) {
        var encodedResult = json.decode(message.result);
        if (_completers[message.id] == null) {
          throw StateError('Missing completer.');
        }
        _completers[message.id]
            .complete(WipResponse(encodedResult as Map<String, dynamic>));
      }
    }, onError: (e) {
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
    _connection.sink.add(jsonEncode(serializers.serialize(ExtensionRequest(
        (b) => b
          ..id = id
          ..command = command
          ..commandParams =
              BuiltMap<String, Object>(params ?? {}).toBuilder()))));
    return completer.future;
  }

  int newId() => _completerId++;

  Future<void> close() async {
    await _connection.sink.close();
  }

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
  Future pause() => sendCommand('Debugger.pause');

  @override
  Future resume() => sendCommand('Debugger.resume');

  @override
  Future setPauseOnExceptions(PauseState state) =>
      sendCommand('Debugger.setPauseOnExceptions',
          params: {'state': _pauseStateToString(state)});

  @override
  Future stepInto() => sendCommand('Debugger.stepInto');

  @override
  Future stepOut() => sendCommand('Debugger.stepOut');

  @override
  Future stepOver() => sendCommand('Debugger.stepOver');

  @override
  Stream<T> eventStream<T>(String method, WipEventTransformer<T> transformer) =>
      throw UnimplementedError();

  @override
  Stream<WipDomain> get onClosed => throw UnimplementedError();

  @override
  Stream<GlobalObjectClearedEvent> get onGlobalObjectCleared =>
      throw UnimplementedError();

  @override
  Stream<DebuggerPausedEvent> get onPaused => throw UnimplementedError();

  @override
  Stream<DebuggerResumedEvent> get onResumed => throw UnimplementedError();

  @override
  Stream<ScriptParsedEvent> get onScriptParsed => throw UnimplementedError();

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
