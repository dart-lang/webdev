// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';
import '../fixtures/utilities.dart';

void main() {
  group('Asset handler', () {
    final context = TestContext();
    Handler assetHandler;
    http.Client client;

    setUpAll(() async {
      await context.setUp(enableExpressionEvaluation: true);

      client = IOClient(HttpClient()
        ..maxConnectionsPerHost = 200
        ..idleTimeout = const Duration(seconds: 30)
        ..connectionTimeout = const Duration(seconds: 30));

      var assetServerPort = daemonPort(context.workingDirectory);
      var pathToServe = context.pathToServe;

      assetHandler = proxyHandler(
          'http://localhost:$assetServerPort/$pathToServe/',
          client: client);
    });

    tearDownAll(() {
      client.close();
    });

    Future<void> readAsString(String path) async {
      var request = Request('GET', Uri.parse('http://foo:0000/$path'));
      var response = await assetHandler(request);
      var result = await response.readAsString();
      expect(result, isNotNull, reason: 'Failed to read $path');
    }

    Future<void> readAsBytes(String path) async {
      var request = Request('GET', Uri.parse('http://foo:0000/$path'));
      var response = await assetHandler(request);
      var result = response.read().toList();
      expect(result, isNotNull, reason: 'Failed to read $path');
    }

    test('can read dill files', () async {
      var path = 'hello_world/main.unsound.ddc.full.dill';
      await readAsBytes(path);
    });

    test('can read large number of resources simultaneously', () async {
      final n = 1000;
      var futures = [
        for (var i = 0; i < n; i++)
          readAsString('hello_world/main.unsound.ddc.js.map'),
        for (var i = 0; i < n; i++)
          readAsString('hello_world/main.unsound.ddc.js'),
        for (var i = 0; i < n; i++)
          readAsBytes('hello_world/main.unsound.ddc.full.dill'),
      ];

      await expectLater(Future.wait(futures), completes);
    });
  });
}
