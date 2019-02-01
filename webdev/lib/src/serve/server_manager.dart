// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build_daemon/data/build_status.dart';

import 'webdev_server.dart';

/// Manages a set of [WebDevServer]s.
///
/// Starts a [WebDevServer] for each target port pair.
class ServerManager {
  final Stream<BuildResults> _buildResults;
  final int _daemonPort;
  final String _hostname;
  final Map<String, int> _targetPorts;
  final bool _logRequests;
  final bool _liveReload;

  final _servers = Set<WebDevServer>();

  ServerManager(
    this._buildResults,
    this._daemonPort,
    this._hostname,
    this._targetPorts,
    this._logRequests,
    this._liveReload,
  );

  Future<void> start() async {
    for (var target in _targetPorts.keys) {
      var server = await WebDevServer.start(
        _hostname,
        _targetPorts[target],
        _daemonPort,
        target,
        _logRequests,
        _liveReload,
        _buildResults,
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
