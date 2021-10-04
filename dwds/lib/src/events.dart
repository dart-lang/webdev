// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';

import 'package:vm_service/vm_service.dart';

class DwdsStats {
  /// The time when the user starts the debugger.
  final DateTime debuggerStart;

  /// The time when dwds launches DevTools.
  DateTime devToolsStart;

  var _isDebuggerReady = false;

  /// Records and returns whether the debugger became ready.
  bool isFirstDebuggerReady() {
    final wasReady = _isDebuggerReady;
    _isDebuggerReady = true;
    return !wasReady;
  }

  DwdsStats(this.debuggerStart);
}

class DwdsEventKind {
  static const String compilerUpdateDependencies =
      'COMPILER_UPDATE_DEPENDENCIES';
  static const String devtoolsLaunch = 'DEVTOOLS_LAUNCH';
  static const String devToolsLoad = 'DEVTOOLS_LOAD';
  static const String debuggerReady = 'DEBUGGER_READY';
  static const String evaluate = 'EVALUATE';
  static const String evaluateInFrame = 'EVALUATE_IN_FRAME';
  static const String getIsolate = 'GET_ISOLATE';
  static const String getScripts = 'GET_SCRIPTS';
  static const String getSourceReport = 'GET_SOURCE_REPORT';
  static const String getVM = 'GET_VM';
  static const String hotRestart = 'HOT_RESTART';
  static const String httpRequestException = 'HTTP_REQUEST_EXCEPTION';
  static const String resume = 'RESUME';

  DwdsEventKind._();
}

class DwdsEvent {
  final String type;
  final Map<String, dynamic> payload;

  DwdsEvent(this.type, this.payload);

  DwdsEvent.compilerUpdateDependencies(String entrypoint)
      : this(DwdsEventKind.compilerUpdateDependencies, {
          'entrypoint': entrypoint,
        });

  DwdsEvent.devtoolsLaunch() : this(DwdsEventKind.devtoolsLaunch, {});

  DwdsEvent.evaluate(String expression, Response result)
      : this(DwdsEventKind.evaluate, {
          'expression': expression,
          'success': result != null && result is InstanceRef,
          if (result != null && result is ErrorRef) 'error': result,
        });

  DwdsEvent.evaluateInFrame(String expression, Response result)
      : this(DwdsEventKind.evaluateInFrame, {
          'expression': expression,
          'success': result != null && result is InstanceRef,
          if (result != null && result is ErrorRef) 'error': result,
        });

  DwdsEvent.getIsolate() : this(DwdsEventKind.getIsolate, {});

  DwdsEvent.getScripts() : this(DwdsEventKind.getScripts, {});

  DwdsEvent.getVM() : this(DwdsEventKind.getVM, {});

  DwdsEvent.resume(String step) : this(DwdsEventKind.resume, {'step': step});

  DwdsEvent.getSourceReport() : this(DwdsEventKind.getSourceReport, {});

  DwdsEvent.hotRestart() : this(DwdsEventKind.hotRestart, {});

  DwdsEvent.debuggerReady(int elapsedMilliseconds)
      : this(DwdsEventKind.debuggerReady, {
          'elapsedMilliseconds': elapsedMilliseconds,
        });

  DwdsEvent.devToolsLoad(int elapsedMilliseconds)
      : this(DwdsEventKind.devToolsLoad, {
          'elapsedMilliseconds': elapsedMilliseconds,
        });

  DwdsEvent.httpRequestException(String server, String exception)
      : this(DwdsEventKind.httpRequestException, {
          'server': server,
          'exception': exception,
        });

  void addException(dynamic exception) {
    payload['exception'] = exception;
  }

  void addElapsedTime(int elapsedMilliseconds) {
    payload['elapsedMilliseconds'] = elapsedMilliseconds;
  }

  @override
  String toString() {
    return 'TYPE: $type Payload: $payload';
  }
}

final _eventController = StreamController<DwdsEvent>.broadcast();

/// Adds an event to the global [eventStream];
void emitEvent(DwdsEvent event) => _eventController.sink.add(event);

/// A global stream of [DwdsEvent]s.
Stream<DwdsEvent> get eventStream => _eventController.stream;

/// Call [function] and record its execution time.
///
/// Calls [event] to create the event to be recorded,
/// and appends time and exception details to it if
/// available.
Future<T> captureElapsedTime<T>(
    Future<T> Function() function, DwdsEvent Function(T result) event) async {
  var stopwatch = Stopwatch()..start();
  T result;
  try {
    return result = await function();
  } catch (e) {
    emitEvent(event(result)
      ..addException(e)
      ..addElapsedTime(stopwatch.elapsedMilliseconds));
    rethrow;
  } finally {
    emitEvent(event(result)..addElapsedTime(stopwatch.elapsedMilliseconds));
  }
}
