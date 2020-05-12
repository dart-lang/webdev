// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/src/stream_sink_transformer.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:dwds/src/utilities/wrapped_service.dart';
import 'package:shelf/shelf.dart' as shelf;
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
  Future<Obj> getObject(String isolateId, String objectId,
          {int offset, int count}) =>
      null;

  @override
  Future<ScriptList> getScripts(String isolateId) => null;

  @override
  Future<ScriptRef> scriptRefFor(String uri) =>
      Future.value(ScriptRef(id: 'fake', uri: 'fake://uri'));

  @override
  ScriptRef scriptWithId(String scriptId) => null;

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

  @override
  void shutdown() {}
}

class FakeWebkitDebugger implements WebkitDebugger {
  @override
  Future disable() => null;

  @override
  Future enable() => null;

  FakeWebkitDebugger() {
    globalLoadStrategy = RequireStrategy(
      ReloadConfiguration.none,
      '.ddc',
      (_) async => {},
      (_) async => {},
      (_) => null,
      (_) => null,
      (_) => null,
    );
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
  Future<WipResponse> pause() => null;

  @override
  Future<WipResponse> resume() => null;

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

    if (method == 'Runtime.evaluate') {
      // Fake response adapted from modules query at google3
      return WipResponse({
        'id': 42,
        'result': {
          'result': <String, dynamic>{
            'type': 'object',
            'value': <String, dynamic>{
              // dart source Uri : js module name
              'dart:io': 'dart_sdk',
              'org-dartlang-app:///dart/tools/iblaze/web/hello_world.dart':
                  'dart/tools/iblaze/web/hello_world_angular_library',
              'package:ads.acx2.rpc.proto_mixin/ess_proto_mixin.dart':
                  'ads/acx2/rpc/proto_mixin/lib/proto_mixin',
              'package:collection/collection.dart: ':
                  'third_party/dart/collection/lib/collection',
              'package:collection/src/algorithms.dart':
                  'third_party/dart/collection/lib/collection',
              'package:shelf/shelf.dart': 'packages/shelf/shelf',
            }
          }
        }
      });
    }

    return null;
  }

  @override
  Future<WipResponse> setPauseOnExceptions(PauseState state) => null;

  @override
  Future<WipResponse> removeBreakpoint(String breakpointId) => null;

  @override
  Future<WipResponse> stepInto() => null;

  @override
  Future<WipResponse> stepOut() => null;

  @override
  Future<WipResponse> stepOver() => null;

  @override
  Stream<ConsoleAPIEvent> get onConsoleAPICalled => null;

  @override
  Stream<ExceptionThrownEvent> get onExceptionThrown => null;

  @override
  void close() {}

  @override
  Stream<WipConnection> get onClose => null;

  @override
  Future<RemoteObject> evaluate(String expression,
          {bool returnByValue, int contextId}) =>
      null;

  @override
  Future<RemoteObject> evaluateOnCallFrame(
      String callFrameId, String expression) async {
    return RemoteObject(<String, dynamic>{});
  }

  @override
  Future<List<WipBreakLocation>> getPossibleBreakpoints(WipLocation start) =>
      null;

  @override
  Future<WipResponse> enablePage() => null;

  @override
  Future<WipResponse> pageReload() => null;
}

/// Fake execution context that is needed for id only
class FakeExecutionContext extends ExecutionContext {
  @override
  Future<int> get id async {
    return 0;
  }

  FakeExecutionContext();
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

class FakeStrategy implements LoadStrategy {
  @override
  Future<String> bootstrapFor(String entrypoint) async => 'dummy_bootstrap';

  @override
  shelf.Handler get handler =>
      (request) => (request.url.path == 'someDummyPath')
          ? shelf.Response.ok('some dummy response')
          : null;

  @override
  String get id => 'dummy-id';

  @override
  String get loadLibrariesSnippet => '';

  @override
  String loadLibrarySnippet(String libraryUri) => '';

  @override
  String get loadModuleSnippet => '';

  @override
  ReloadConfiguration get reloadConfiguration => ReloadConfiguration.none;

  @override
  String loadClientSnippet(String clientScript) => 'dummy-load-client-snippet';

  @override
  String moduleForServerPath(String serverPath) => null;

  @override
  String serverPathForModule(String module) => null;

  @override
  String serverPathForAppUri(String appUri) => null;
}
