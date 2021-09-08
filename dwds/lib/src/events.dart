// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';

class DwdsStats {
  /// Timestamp for the point when the user starts the debugger
  /// by either clicking the debugger extension button or
  /// starting debugging in the UI.
  final DateTime debuggerStart;

  /// Timestamp for the point when the debugger becomes
  /// available and fuctional for the user.
  DateTime _debuggerReady;
  DateTime get debuggerReady => _debuggerReady;
  set debuggerReady(DateTime value) => _debuggerReady ??= value;

  int get debuggerReadyElapsed {
    if (debuggerStart == null) {
      throw StateError('debuggerStart is not set in DwdsStats');
    }
    if (_debuggerReady == null) {
      throw StateError('debuggerReady is not set in DwdsStats');
    }
    return _debuggerReady.millisecondsSinceEpoch -
        debuggerStart.millisecondsSinceEpoch;
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
