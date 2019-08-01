// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:stream_channel/src/stream_channel_transformer.dart';
import 'package:stream_channel/stream_channel.dart';

/// A library of fake/stub implementations of our classes and their supporting
/// classes (e.g. WipConnection) for unit testing.
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'debugger_data.dart';

class FakeInspector extends Domain implements AppInspector {
  FakeInspector() : super.forInspector();
  @override
  Future<RemoteObject> evaluate(
          String isolateId, String targetId, String expression,
          {Map<String, String> scope, bool disableBreakpoints}) =>
      null;
  @override
  Future getObject(String isolateId, String objectId,
          {int offset, int count}) =>
      null;
  @override
  Future<ScriptList> getScripts(String isolateId) => null;
  @override
  Future<InstanceRef> instanceRefFor(RemoteObject remoteObject) => null;
  @override
  Future<ScriptRef> scriptRefFor(String uri) => null;
  @override
  Future<List<ScriptRef>> scriptRefs(String isolateId) => null;
  @override
  Future<ScriptRef> scriptWithId(String scriptId) => null;
  @override
  Isolate checkIsolate(String isolateId) => null;
  @override
  Isolate get isolate => null;
  @override
  IsolateRef get isolateRef => null;
  @override
  Future loadField(RemoteObject receiver, String fieldName) => null;
  @override
  Future<Map<String, Object>> sendMessage(
          RemoteObject receiver, String methodName,
          [List positionalArgs = const [], Map namedArgs = const {}]) =>
      null;
  @override
  Debugger get debugger => null;
  @override
  Future<RemoteObject> callJsFunctionOn(
          Library library, Map<String, String> scope, String expression) =>
      null;
  @override
  Future<RemoteObject> evaluateJsExpression(String expression) => null;
  @override
  Future<RemoteObject> evaluateJsExpressionOnLibrary(
          String expression, String libraryUri) =>
      null;
  @override
  Future<String> toStringOf(RemoteObject receiver) async => '';
}

class FakeSseConnection implements SseConnection {
  @override
  StreamChannel<S> cast<S>() => null;

  /// A [StreamController] for incoming messages on SSE connection.
  final controllerIncoming = StreamController<String>();

  /// A [StreamController] for outgoing messages on SSE connection.
  final controllerOutgoing = StreamController<String>();

  @override
  StreamChannel<String> changeSink(
          StreamSink<String> Function(StreamSink<String> sink) change) =>
      null;

  @override
  StreamChannel<String> changeStream(
          Stream<String> Function(Stream<String> stream) change) =>
      null;

  @override
  void pipe(StreamChannel<String> other) {}

  @override
  StreamSink<String> get sink => controllerOutgoing.sink;

  @override
  Stream<String> get stream => controllerIncoming.stream;

  @override
  StreamChannel<S> transform<S>(
          StreamChannelTransformer<S, String> transformer) =>
      null;

  @override
  StreamChannel<String> transformSink(
          StreamSinkTransformer<String, String> transformer) =>
      null;

  @override
  StreamChannel<String> transformStream(
          StreamTransformer<String, String> transformer) =>
      null;
}

class FakeWipDebugger implements WipDebugger {
  @override
  WipConnection get connection => null;

  @override
  Future disable() => null;

  @override
  Future enable() => null;

  @override
  Stream<T> eventStream<T>(String method, WipEventTransformer<T> transformer) =>
      null;

  @override
  Future<String> getScriptSource(String scriptId) => null;

  @override
  Stream<WipDomain> get onClosed => null;

  @override
  Stream<GlobalObjectClearedEvent> get onGlobalObjectCleared => null;

  @override
  Stream<DebuggerPausedEvent> get onPaused => null;

  @override
  Stream<DebuggerResumedEvent> get onResumed => null;

  @override
  Stream<ScriptParsedEvent> get onScriptParsed => null;

  @override
  Future pause() => null;
  @override
  Future resume() => null;

  @override
  Map<String, WipScript> get scripts => null;

  List<WipResponse> results = variables1;
  int resultsReturned = 0;

  @override
  Future<WipResponse> sendCommand(
    String method, {
    Map<String, dynamic> params,
  }) async {
    // Force the results that we expect for looking up the variables.
    if (method == 'Runtime.getProperties') {
      return results[resultsReturned++];
    }
    return null;
  }

  @override
  Future setPauseOnExceptions(PauseState state) => null;

  @override
  Future stepInto() => null;

  @override
  Future stepOut() => null;

  @override
  Future stepOver() => null;
}
