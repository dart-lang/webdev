// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:dwds/src/utilities/wrapped_service.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:stream_channel/src/stream_channel_transformer.dart';
import 'package:stream_channel/stream_channel.dart';

/// A library of fake/stub implementations of our classes and their supporting
/// classes (e.g. WipConnection) for unit testing.
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'debugger_data.dart';

/// Constructs a trivial Isolate we can use when we need to provide one but
/// don't want go through initialization.
Isolate get simpleIsolate => Isolate(
      id: '1',
      number: '1',
      name: 'fake',
      libraries: [],
      exceptionPauseMode: 'abc',
      breakpoints: [],
      pauseOnExit: false,
      pauseEvent: null,
      startTime: 0,
      livePorts: 0,
      runnable: false,
    );

class FakeInspector extends Domain implements AppInspector {
  FakeInspector({this.fakeIsolate}) : super.forInspector();

  Isolate fakeIsolate;

  @override
  Object noSuchMethod(Invocation invocation) {
    throw UnsupportedError('This is a fake');
  }

  @override
  Future<RemoteObject> evaluate(
          String isolateId, String targetId, String expression,
          {Map<String, String> scope}) =>
      null;
  @override
  Future getObject(String isolateId, String objectId,
          {int offset, int count}) =>
      null;
  @override
  Future<ScriptList> getScripts(String isolateId) => null;
  @override
  Future<ScriptRef> scriptRefFor(String uri) =>
      Future.value(ScriptRef(id: 'fake', uri: 'fake://uri'));
  @override
  Future<ScriptRef> scriptWithId(String scriptId) => null;
  @override
  Isolate checkIsolate(String isolateId) => fakeIsolate;
  @override
  Isolate get isolate => fakeIsolate;
  @override
  IsolateRef get isolateRef => null;
  @override
  InstanceHelper get instanceHelper => InstanceHelper(null);
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
  bool get isInKeepAlivePeriod => false;

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

class FakeWebkitDebugger implements WebkitDebugger {
  @override
  Future disable() => null;

  @override
  Future enable() => null;

  FakeWebkitDebugger() {
    globalLoadStrategy = RequireStrategy(
        ReloadConfiguration.none, '.ddc', (_) async => {}, (_) async => {});
  }

  @override
  Stream<T> eventStream<T>(String method, WipEventTransformer<T> transformer) =>
      null;

  @override
  Future<String> getScriptSource(String scriptId) => null;

  Stream<WipDomain> get onClosed => null;

  @override
  Stream<GlobalObjectClearedEvent> get onGlobalObjectCleared => null;

  @override
  Stream<DebuggerPausedEvent> onPaused;

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
    if (method == 'Debugger.evaluateOnCallFrame') {
      return WipResponse({
        'id': 42,
        'result': {'result': <String, dynamic>{}}
      });
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

  @override
  Stream<ConsoleAPIEvent> get onConsoleAPICalled => null;

  @override
  Stream<ExceptionThrownEvent> get onExceptionThrown => null;

  @override
  void close() {}

  @override
  Stream<WipConnection> get onClose => null;

  @override
  Future<RemoteObject> evaluate(String expression) => null;

  @override
  Future<void> enablePage() => null;
}

/// Fake expression compiler that simply passes expression through,
/// without actual compilation
class FakeExpressionCompiler implements ExpressionCompiler {
  @override
  Future<ExpressionCompilationResult> compileExpressionToJs(
      String isolateId,
      String libraryUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression) async {
    return ExpressionCompilationResult('''
      try {
        (function(x) {
          let main = require('example/hello_world/main').main;
          let dart = require('dart_sdk').dart;
          let core = require('dart_sdk').core;
          console.log(x);
          return x;
        }(
          $expression
        ))
        } catch (error) {
          console.error(error.name + ": " + error.message);
          error.name + ": " + error.message;
        }''', false);
  }
}
