// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';

class DwdsStats {
  /// The time when the user starts the debugger.
  final DateTime debuggerStart;

  var _isDebuggerReady = false;

  /// Records and returns whether the debugger became ready.
  bool isFirstDebuggerReady() {
    final wasReady = _isDebuggerReady;
    _isDebuggerReady = true;
    return !wasReady;
  }

  DwdsStats(this.debuggerStart);
}

class DwdsEvent {
  final String type;
  final Map<String, dynamic> payload;

  DwdsEvent(this.type, this.payload);

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
