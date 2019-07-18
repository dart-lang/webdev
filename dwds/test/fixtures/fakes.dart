// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:stream_channel/src/stream_channel_transformer.dart';
import 'package:stream_channel/stream_channel.dart';

/// A library of fake/stub implementations of our classes and their supporting
/// classes (e.g. WipConnection) for unit testing.
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

class FakeWipConnection implements WipConnection {
  @override
  Future close() async {}
  @override
  Future<WipResponse> sendCommand(String method,
          [Map<String, dynamic> foo]) async =>
      null;

  WipRuntime _runtime;

  @override
  WipConsole get console => null; // ignore: deprecated_member_use
  @override
  WipDebugger get debugger => null;
  @override
  WipDom get dom => null;
  @override
  WipLog get log => null;
  @override
  Stream<WipConnection> get onClose => null;
  @override
  Stream<WipEvent> get onNotification => null;
  @override
  WipPage get page => null;
  @override
  WipRuntime get runtime =>
      _runtime == null ? _runtime = FakeRuntime(this) : _runtime;
  @override
  WipTarget get target => null;
  @override
  String get url => null;
}

class FakeInspector extends Domain implements AppInspector {
  FakeInspector() : super.forInspector();
  @override
  Future evaluate(String isolateId, String targetId, String expression,
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
}

/// A stub for [WipRuntime].
///
/// This allows you to specify a sequence of results that will be returned from
/// sendCommand, if the sendCommand calls are sent in exactly the right order.
class FakeRuntime extends WipRuntime {
  FakeRuntime(WipConnection connection) : super(connection);

  List<WipResponse> results = [];
  int resultsReturned = 0;

  @override
  Future<WipResponse> sendCommand(
    String method, {
    Map<String, dynamic> params,
  }) async {
    return results[resultsReturned++];
  }
}

class FakeSseConnection implements SseConnection {
  @override
  StreamChannel<S> cast<S>() => null;

  final _controller = StreamController<String>();

  StreamController<String> get controller => _controller;

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
  StreamSink<String> get sink => controller.sink;

  @override
  Stream<String> get stream => controller.stream;

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
