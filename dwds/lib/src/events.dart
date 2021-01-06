// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

class DwdsEvent {
  final String type;
  final Map<String, dynamic> payload;

  DwdsEvent(this.type, this.payload);
}

final _eventController = StreamController<DwdsEvent>();

/// Adds an event to the global [eventStream];
void emitEvent(DwdsEvent event) => _eventController.sink.add(event);

/// A global stream of [DwdsEvent]s.
Stream<DwdsEvent> get eventStream =>
    _eventController.stream.asBroadcastStream();
