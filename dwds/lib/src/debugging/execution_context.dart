// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:logging/logging.dart';

import 'remote_debugger.dart';

abstract class ExecutionContext {
  /// Returns the context ID that contains the running Dart application.
  Future<int> get id;
}

/// The execution context in which to do remote evaluations.
class RemoteDebuggerExecutionContext extends ExecutionContext {
  final RemoteDebugger _remoteDebugger;
  final _logger = Logger('RemoteDebuggerExecutionContext');

  // Contexts that may contain a Dart application.
  late StreamQueue<int?> _contexts;

  int? _id;

  @override
  Future<int> get id async {
    if (_id != null) return _id!;
    _logger.fine('Looking for Dart execution context...');
    while (await _contexts.hasNext
        .timeout(const Duration(milliseconds: 50), onTimeout: () => false)) {
      var context = await _contexts.next;
      _logger.fine('Checking context id: $context');
      try {
        var result =
            await _remoteDebugger.sendCommand('Runtime.evaluate', params: {
          'expression': r'window["$dartAppInstanceId"];',
          'contextId': context,
        });
        if (result.result?['result']?['value'] != null) {
          _logger.fine('Found valid execution context: $context');
          _id = context;
          break;
        }
      } catch (_) {
        // Errors may be thrown if we attempt to evaluate in a stale a context.
        // Ignore and continue.
        _logger.fine('Invalid execution context: $context');
      }
    }
    if (_id == null) {
      throw StateError('No context with the running Dart application.');
    }
    return _id!;
  }

  RemoteDebuggerExecutionContext(this._id, this._remoteDebugger) {
    var contextController = StreamController<int?>();
    _remoteDebugger
        .eventStream('Runtime.executionContextsCleared', (e) => e)
        .listen((_) => _id = null);
    _remoteDebugger.eventStream('Runtime.executionContextCreated', (e) {
      var id = e.params?['context']?['id']?.toString();
      return id == null ? null : int.parse(id);
    }).listen(contextController.add);
    _contexts = StreamQueue(contextController.stream);
  }
}
