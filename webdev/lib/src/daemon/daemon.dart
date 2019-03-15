// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'domain.dart';
import 'utilites.dart';

/// A collection of domains.
///
/// Listens for commands, routes them to the corresponding domain and provides
/// the result.
class Daemon {
  Daemon(
    Stream<Map<String, dynamic>> commandStream,
    this._sendCommand,
  ) {
    _commandSubscription = commandStream.listen(
      _handleRequest,
      onDone: () {
        if (!_onExitCompleter.isCompleted) _onExitCompleter.complete(0);
      },
    );
  }

  StreamSubscription<Map<String, dynamic>> _commandSubscription;

  final void Function(Map<String, dynamic>) _sendCommand;

  final Completer<int> _onExitCompleter = Completer<int>();
  final Map<String, Domain> _domainMap = <String, Domain>{};

  void registerDomain(Domain domain) {
    if (_domainMap.containsKey(domain.name)) {
      throw StateError('${domain.name} already registered.');
    }
    _domainMap[domain.name] = domain;
  }

  Future<int> get onExit => _onExitCompleter.future;

  void _handleRequest(Map<String, dynamic> request) {
    // {id, method, params}

    // [id] is an opaque type to us.
    var id = request['id'];

    if (id == null) {
      stderr.writeln('no id for request: $request');
      return;
    }

    try {
      var method = request['method'] as String ?? '';
      if (!method.contains('.')) {
        throw ArgumentError('method not understood: $method');
      }

      var domain = method.substring(0, method.indexOf('.'));
      var name = method.substring(method.indexOf('.') + 1);
      if (_domainMap[domain] == null) {
        throw ArgumentError('no domain for method: $method');
      }

      _domainMap[domain].handleCommand(
          name, id, request['params'] as Map<String, dynamic> ?? {});
    } catch (error, trace) {
      send(<String, dynamic>{
        'id': id,
        'error': toJsonable(error),
        'trace': '$trace',
      });
    }
  }

  void send(Map<String, dynamic> map) => _sendCommand(map);

  void shutdown({dynamic error}) {
    _commandSubscription?.cancel();
    for (var domain in _domainMap.values) domain.dispose();
    if (!_onExitCompleter.isCompleted) {
      if (error == null) {
        _onExitCompleter.complete(0);
      } else {
        _onExitCompleter.completeError(error);
      }
    }
  }
}
