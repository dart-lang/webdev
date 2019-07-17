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

/// A debugger backed by the Dart Debug Extension
class ExtensionDebugger implements WipDebugger {
  @override
  WipConnection get connection => throw UnimplementedError();

  /// A connection between the debugger and the background of
  /// Dart Debug Extension
  final SseConnection _connection;

  /// A map from [completerId] to a completer associated with
  /// an [ExtensionRequest]
  final completers = <int, Completer>{};

  var completerId = 0;

  ExtensionDebugger(this._connection) {
    _connection.stream.listen((data) {
      var message = serializers.deserialize(jsonDecode(data));
      if (message is ExtensionResponse) {
        var encodedResult = json.decode(message.result);
        if (completers[message.id] == null) {
          throw StateError('Missing completer.');
        }
        completers[message.id]
            .complete(WipResponse(encodedResult as Map<String, dynamic>));
      }
    }, onError: (e) {
      close();
    });
  }

  /// Sends a [command] with optional [params] to Dart Debug Extension
  /// over the SSE connection.
  ///
  /// Each sent command has a unique id [completerId].
  @override
  Future<WipResponse> sendCommand(String command,
      {Map<String, dynamic> params}) {
    var completer = Completer<WipResponse>();
    var id = newId();
    completers[id] = completer;
    _connection.sink.add(jsonEncode(serializers.serialize(ExtensionRequest(
        (b) => b
          ..id = id
          ..command = command
          ..commandParams =
              BuiltMap<String, Object>(params ?? {}).toBuilder()))));
    return completer.future;
  }

  int newId() => completerId++;

  Future<void> close() async {
    await _connection.sink.close();
  }

  @override
  Future disable() => throw UnimplementedError();

  @override
  Future enable() => throw UnimplementedError();

  @override
  Stream<T> eventStream<T>(String method, WipEventTransformer<T> transformer) =>
      throw UnimplementedError();

  @override
  Future<String> getScriptSource(String scriptId) => throw UnimplementedError();

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
  Future pause() => throw UnimplementedError();

  @override
  Future resume() => throw UnimplementedError();

  @override
  Map<String, WipScript> get scripts => throw UnimplementedError();

  @override
  Future setPauseOnExceptions(PauseState state) => throw UnimplementedError();

  @override
  Future stepInto() => throw UnimplementedError();

  @override
  Future stepOut() => throw UnimplementedError();

  @override
  Future stepOver() => throw UnimplementedError();
}
