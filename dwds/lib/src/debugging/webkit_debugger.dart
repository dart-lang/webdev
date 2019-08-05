// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// A remote debugger with a Webkit Inspection Protocol connection.
class WebkitDebugger implements RemoteDebugger {
  final WipDebugger _wipDebugger;

  WebkitDebugger(this._wipDebugger);

  WipConnection get connection => _wipDebugger.connection;

  @override
  Stream<ConsoleAPIEvent> get onConsoleAPICalled =>
      _wipDebugger.connection.runtime.onConsoleAPICalled;

  @override
  Stream<ExceptionThrownEvent> get onExceptionThrown =>
      _wipDebugger.connection.runtime.onExceptionThrown;

  @override
  Future<WipResponse> sendCommand(String command,
          {Map<String, dynamic> params}) =>
      _wipDebugger.sendCommand(command, params: params);

  @override
  Future disable() => _wipDebugger.disable();

  @override
  Future enable() => _wipDebugger.enable();

  @override
  Future<String> getScriptSource(String scriptId) =>
      _wipDebugger.getScriptSource(scriptId);

  @override
  Future pause() => _wipDebugger.pause();

  @override
  Future resume() => _wipDebugger.resume();

  @override
  Future setPauseOnExceptions(PauseState state) =>
      _wipDebugger.setPauseOnExceptions(state);

  @override
  Future stepInto() => _wipDebugger.stepInto();

  @override
  Future stepOut() => _wipDebugger.stepOut();

  @override
  Future stepOver() => _wipDebugger.stepOver();

  @override
  Stream<T> eventStream<T>(String method, WipEventTransformer<T> transformer) =>
      _wipDebugger.eventStream(method, transformer);

  @override
  Stream<GlobalObjectClearedEvent> get onGlobalObjectCleared =>
      _wipDebugger.onGlobalObjectCleared;

  @override
  Stream<DebuggerPausedEvent> get onPaused => _wipDebugger.onPaused;

  @override
  Stream<DebuggerResumedEvent> get onResumed => _wipDebugger.onResumed;

  @override
  Stream<ScriptParsedEvent> get onScriptParsed => _wipDebugger.onScriptParsed;

  @override
  Map<String, WipScript> get scripts => _wipDebugger.scripts;
}
