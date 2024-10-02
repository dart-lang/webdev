// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build_daemon/data/build_status.dart';

import 'webdev_server.dart';

/// Manages a set of [WebDevServer]s.
class ServerManager {
  final Set<WebDevServer> servers;

  ServerManager._(this.servers);

  static Future<ServerManager> start(
    Set<ServerOptions> serverOptions,
    Stream<BuildResults> buildResults,
  ) async {
    final servers = <WebDevServer>{};
    for (final options in serverOptions) {
      servers.add(await WebDevServer.start(options, buildResults));
    }
    return ServerManager._(servers);
  }

  Future<void> stop() async {
    for (final server in servers) {
      await server.stop();
    }
  }
}
