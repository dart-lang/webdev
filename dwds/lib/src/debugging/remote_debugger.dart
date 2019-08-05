// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// A generic debugger used in remote debugging.
abstract class RemoteDebugger {
  Stream<ConsoleAPIEvent> get onConsoleAPICalled;
  Stream<ExceptionThrownEvent> get onExceptionThrown;
  Future<WipResponse> sendCommand(String command,
      {Map<String, dynamic> params});
  Future disable();
  Future enable();
  Future<String> getScriptSource(String scriptId);
  Future pause();
  Future resume();
  Future setPauseOnExceptions(PauseState state);
  Future stepInto();
  Future stepOut();
  Future stepOver();
  Stream<T> eventStream<T>(String method, WipEventTransformer<T> transformer);
  Stream<GlobalObjectClearedEvent> get onGlobalObjectCleared;
  Stream<DebuggerPausedEvent> get onPaused;
  Stream<DebuggerResumedEvent> get onResumed;
  Stream<ScriptParsedEvent> get onScriptParsed;
  Map<String, WipScript> get scripts;
}
