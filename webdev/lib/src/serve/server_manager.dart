// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build_daemon/data/build_status.dart';

import 'webdev_server.dart';

/// Manages a set of [WebDevServer]s.
class ServerManager {
  final Stream<BuildResults> _buildResults;
  final Set<ServerOptions> _serverOptions;
  final _servers = Set<WebDevServer>();

  ServerManager(this._serverOptions, this._buildResults);

  List<String> get uris =>
      _servers.map((s) => 'http://${s.host}:${s.port}').toList();

  Future<void> start() async {
    for (var options in _serverOptions) {
      _servers.add(await WebDevServer.start(
        options,
        _buildResults,
      ));
    }
  }

  Future<void> stop() async {
    for (var server in _servers) {
      await server.stop();
    }
  }
}
