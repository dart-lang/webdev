// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import '../serve/controller.dart';
import 'app_domain.dart';
import 'daemon_domain.dart';
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
    Future<ServeController> futureServeController,
  ) {
    _registerDomain(DaemonDomain(this));
    _registerDomain(AppDomain(this, futureServeController));

    // TODO(grouma) - complete these other domains.
    //_registerDomain(deviceDomain = DeviceDomain(this));
    //_registerDomain(emulatorDomain = EmulatorDomain(this));

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

  void _registerDomain(Domain domain) {
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

  void sendEvent(String domain, String name, [dynamic args]) =>
      _domainMap[domain].sendEvent('$domain.$name', args);

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
