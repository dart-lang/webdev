// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// A remote debugger with a Webkit Inspection Protocol connection.
class WebkitDebugger implements RemoteDebugger {
  final WipDebugger _wipDebugger;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  WebkitDebugger(this._wipDebugger);

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
  void close() => _closed ??= _wipDebugger.connection.close();

  @override
  Future<void> disable() => _wipDebugger.disable();

  @override
  Future<void> enable() => _wipDebugger.enable();

  @override
  Future<String> getScriptSource(String scriptId) =>
      _wipDebugger.getScriptSource(scriptId);

  @override
  Future<void> pause() => _wipDebugger.pause();

  @override
  Future<void> resume() => _wipDebugger.resume();

  @override
  Future<void> setPauseOnExceptions(PauseState state) =>
      _wipDebugger.setPauseOnExceptions(state);

  @override
  Future<void> stepInto() => _wipDebugger.stepInto();

  @override
  Future<void> stepOut() => _wipDebugger.stepOut();

  @override
  Future<void> stepOver() => _wipDebugger.stepOver();

  @override
  Future<void> enablePage() => _wipDebugger.connection.page.enable();

  @override
  Future<void> pageReload() => _wipDebugger.connection.page.reload();

  @override
  Future<RemoteObject> evaluate(String expression) =>
      _wipDebugger.connection.runtime.evaluate(expression);

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

  @override
  Stream<WipConnection> get onClose => _wipDebugger.connection.onClose;
}
