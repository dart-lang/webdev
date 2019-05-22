// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:http_multi_server/http_multi_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_static/shelf_static.dart';

/// A server for Dart Devtools.
class DevTools {
  final String hostname;
  final int port;
  final HttpServer _server;

  DevTools._(this.hostname, this.port, this._server);

  Future<void> close() async {
    await _server.close();
  }

  static Future<DevTools> start(String hostname) async {
    var resourceUri = await Isolate.resolvePackageUri(
        Uri(scheme: 'package', path: 'devtools/devtools.dart'));
    final packageDir = p.dirname(p.dirname(resourceUri.toFilePath()));

    // Default static handler for all non-package requests.
    var buildDir = p.join(packageDir, 'build');
    final buildHandler =
        createStaticHandler(buildDir, defaultDocument: 'index.html');

    // The packages folder is renamed in the pub package so this handler serves
    // out of the `pack` folder.
    var packagesDir = p.join(packageDir, 'build', 'pack');
    var packHandler =
        createStaticHandler(packagesDir, defaultDocument: 'index.html');

    // Make a handler that delegates to the correct handler based on path.
    var handler = (Request request) {
      return request.url.path.startsWith('packages/')
          // request.change here will strip the `packages` prefix from the path
          // so it's relative to packHandler's root.
          ? packHandler(request.change(path: 'packages'))
          : buildHandler(request);
    };

    var server = hostname == 'localhost'
        ? await HttpMultiServer.loopback(0)
        : await HttpServer.bind(hostname, 0);
    serveRequests(server, handler);

    return DevTools._(server.address.host, server.port, server);
  }
}
