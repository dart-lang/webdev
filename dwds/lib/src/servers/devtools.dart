// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:devtools_server/devtools_server.dart';

/// A server for Dart Devtools.
class DevTools {
  final String hostname;
  final int port;
  final HttpServer _server;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  DevTools._(this.hostname, this.port, this._server);

  Future<void> close() => _closed ??= _server.close();

  static Future<DevTools> start(String hostname) async {
    var server =
        await serveDevTools(hostname: hostname, enableStdinCommands: false);
    return DevTools._(server.address.host, server.port, server);
  }
}
