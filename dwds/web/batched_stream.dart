// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';
import 'package:async/async.dart';

/// Stream controller allowing to batch events.
class BatchedStreamController<T> {
  static const _batchDelayMilliseconds = 1000;
  static const _checkDelayMilliseconds = 100;

  final int _batchDelay;

  StreamController<T> _inputController;
  StreamQueue<T> _inputQueue;

  StreamController<List<T>> _outputController;
  final Completer<bool> _completer = Completer<bool>();

  /// Create batched stream controller.
  ///
  /// Collects events from input [sink] and emits them in batches to the
  /// output [stream] every [delay] milliseconds. Keeps the original order.
  BatchedStreamController({
    int delay = _batchDelayMilliseconds,
  }) : _batchDelay = delay {
    _inputController = StreamController<T>();
    _inputQueue = StreamQueue<T>(_inputController.stream);
    _outputController = StreamController<List<T>>();

    unawaited(_batchAndSendEvents());
  }

  /// Sink collecting events.
  StreamSink<T> get sink => _inputController.sink;

  /// Output stream of batch events.
  Stream<List<T>> get stream => _outputController.stream;

  /// Close the controller.
  Future<dynamic> close() async {
    unawaited(_inputController.close());
    return _completer.future.then((value) => _outputController.close());
  }

  /// Send events to the output in a batch every [_batchDelay].
  Future<void> _batchAndSendEvents() async {
    const duration = Duration(milliseconds: _checkDelayMilliseconds);
    var buffer = <T>[];

    var lastSendTime = DateTime.now().millisecondsSinceEpoch;
    while (await _inputQueue.hasNext.timeout(duration, onTimeout: () => true)) {
      if (await _inputQueue.hasNext.timeout(duration, onTimeout: () => false)) {
        buffer.add(await _inputQueue.next);
      }

      var now = DateTime.now().millisecondsSinceEpoch;
      if (now > lastSendTime + _batchDelay) {
        lastSendTime = now;
        if (buffer.isNotEmpty) {
          _outputController.sink.add(List.from(buffer));
          buffer.clear();
        }
      }
    }

    if (buffer.isNotEmpty) {
      _outputController.sink.add(List.from(buffer));
    }
    _completer.complete(true);
  }
}
