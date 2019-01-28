// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'webdev_server.dart';

/// Manages a set of [WebDevServer]s.
///
/// Starts a [WebDevServer] for each target port pair.
class ServerManager {
  final int _daemonPort;
  final String _hostname;
  final Map<String, int> _targetPorts;
  final bool _logRequests;

  final _servers = Set<WebDevServer>();

  ServerManager(
    this._daemonPort,
    this._hostname,
    this._targetPorts,
    this._logRequests,
  );

  Future<void> start() async {
    for (var target in _targetPorts.keys) {
      var server = await WebDevServer.start(
        _hostname,
        _targetPorts[target],
        _daemonPort,
        target,
        _logRequests,
      );
      _servers.add(server);
    }
  }

  Future<void> stop() async {
    for (var server in _servers) {
      await server.stop();
    }
  }
}
