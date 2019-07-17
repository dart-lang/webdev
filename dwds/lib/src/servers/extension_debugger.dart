import 'dart:async';
import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../data/serializers.dart';

/// A debugger for Dart Debug Extension.
///
/// The SseHandler listens for ExtensionResponse sent from the SseClient in
/// the background of Dart Debug Extension.
class ExtensionDebugger implements WipDebugger {
  @override
  WipConnection get connection => throw UnimplementedError();
  final SseConnection _connection;
  var completers = <int, Completer>{};
  var completerId = 0;
  ExtensionDebugger(this._connection) {
    _connection.stream.listen((data) {
      var message = serializers.deserialize(jsonDecode(data));
      if (message is ExtensionResponse) {
        var encodedResult = json.decode(message.result);
        if (completers[message.id] == null) {
          throw Exception('Missing completer.');
        }
        completers[message.id]
            .complete(WipResponse(encodedResult as Map<String, dynamic>));
      }
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
    completers[completerId] = completer;
    _connection.sink.add(jsonEncode(serializers.serialize(ExtensionRequest(
        (b) => b
          ..id = completerId
          ..command = command
          ..commandParams =
              BuiltMap<String, Object>(params ?? {}).toBuilder()))));
    completerId += 1;
    return completer.future;
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
