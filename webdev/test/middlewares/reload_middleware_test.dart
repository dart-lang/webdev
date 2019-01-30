// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:webdev/src/serve/middlewares/reload_middleware.dart';

void main() {
  HttpServer server;

  group('ReloadMiddleware', () {
    setUp(() async {
      var pipeline = const Pipeline().addMiddleware(injectLiveReloadClientCode);
      server = await shelf_io.serve(pipeline.addHandler((request) {
        if (request.url.path.endsWith('entrypoint.js')) {
          return Response.ok('$entrypointExtensionMarker',
              headers: {HttpHeaders.etagHeader: 'entry etag'});
        } else if (request.url.path.endsWith('foo.js')) {
          return Response.ok('some js',
              headers: {HttpHeaders.etagHeader: 'some etag'});
        } else {
          return Response.notFound('Not found');
        }
      }), 'localhost', 0);
    });

    tearDown(() async {
      await server.close();
    });

    test('leaves non-entrypoints untouched', () async {
      var result = await http.get('http://localhost:${server.port}/foo.js');
      expect(result.body, 'some js');
    });

    test('does not update etags for non-entrypoints', () async {
      var result = await http.get('http://localhost:${server.port}/foo.js');
      expect(result.headers[HttpHeaders.etagHeader], 'some etag');
    });

    test('injects client for entrypoints', () async {
      var result =
          await http.get('http://localhost:${server.port}/entrypoint.js');
      expect(result.body.contains('Injected by webdev'), isTrue);
    });

    test('updates etags for injected responses', () async {
      var result =
          await http.get('http://localhost:${server.port}/entrypoint.js');
      expect(result.headers[HttpHeaders.etagHeader], isNot('entry etag'));
    });

    test('ignores non-js requests', () async {
      var result = await http.get('http://localhost:${server.port}/main.dart');
      expect(result.body, 'Not found');
    });
  });
}
