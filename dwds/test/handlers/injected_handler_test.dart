// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:dwds/src/handlers/injected_handler.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/version.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

class FakeStrategy implements LoadStrategy {
  @override
  Future<String> bootstrapFor(String entrypoint) async => 'dummy_bootstrap';

  @override
  Handler get handler => (request) => (request.url.path == 'someDummyPath')
      ? Response.ok('some dummy response')
      : null;

  @override
  String get id => 'dummy-id';

  @override
  String get loadLibrariesSnippet => '';

  @override
  String loadLibrarySnippet(String libraryUri) => '';

  @override
  String get loadModuleSnippet => '';

  @override
  ReloadConfiguration get reloadConfiguration => ReloadConfiguration.none;

  @override
  String loadClientSnippet(String clientScript) => 'dummy-load-client-snippet';

  @override
  String moduleForServerPath(String serverPath) => '';

  @override
  String serverPathForModule(String server) => '';
}

void main() {
  HttpServer server;
  const entryEtag = 'entry etag';
  const nonEntryEtag = 'some etag';
  const encodedUrl = 'http://some-host:1000/foo';
  var loadStrategy = FakeStrategy();

  group('InjectedHandlerWithoutExtension', () {
    setUp(() async {
      var pipeline = const Pipeline().addMiddleware(createInjectedHandler(
          loadStrategy,
          urlEncoder: (url) async => encodedUrl));
      server = await shelf_io.serve(pipeline.addHandler((request) {
        if (request.url.path.endsWith(bootstrapJsExtension)) {
          return Response.ok(
              '$entrypointExtensionMarker\n'
              '$mainExtensionMarker\n'
              'app.main.main()',
              headers: {HttpHeaders.etagHeader: entryEtag});
        } else if (request.url.path.endsWith('foo.js')) {
          return Response.ok('some js',
              headers: {HttpHeaders.etagHeader: nonEntryEtag});
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
      expect(result.headers[HttpHeaders.etagHeader], nonEntryEtag);
    });

    test('replaces main marker with injected client', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.body.contains('Injected by webdev'), isTrue);
      expect(result.body.contains(mainExtensionMarker), isFalse);
    });

    test('prevents main from being called', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.body.contains('app.main.main()'), isFalse);
    });

    test('updates etags for injected responses', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.headers[HttpHeaders.etagHeader], isNot(entryEtag));
    });

    test('ignores non-js requests', () async {
      var result = await http.get('http://localhost:${server.port}/main.dart');
      expect(result.body, 'Not found');
    });

    test('correctly encodes dartUriBase', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(
          result.body.contains('window.\$dartUriBase = "$encodedUrl"'), isTrue);
    });

    test(
        'Does not return 304 when if-none-match etag matches the original '
        'content etag', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension',
          headers: {HttpHeaders.ifNoneMatchHeader: entryEtag});
      expect(result.statusCode, HttpStatus.ok);
    });

    test('Does return 304 when if-none-match etag matches the modified etag',
        () async {
      var originalResponse = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      var cachedResponse = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension',
          headers: {
            HttpHeaders.ifNoneMatchHeader:
                originalResponse.headers[HttpHeaders.etagHeader]
          });
      expect(cachedResponse.statusCode, HttpStatus.notModified);
    });

    test('Does not inject the extension backend port', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.body.contains('dartExtensionUri'), isFalse);
    });

    test('Has correct DWDS version', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      var expected = r'$dwdsVersion = ';
      var index = result.body.indexOf(expected);
      expect(index, greaterThan(0));
      var nextBit = result.body.substring(index + expected.length);
      var versionPiece = nextBit.split('"')[1];
      expect(versionPiece, packageVersion);
    });

    test('Injects bootstrap', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.body.contains('dummy_bootstrap'), isTrue);
    });

    test('Injects load strategy id', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.body.contains('dummy-id'), isTrue);
    });

    test('Injects client load snippet', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.body.contains('dummy-load-client-snippet'), isTrue);
    });

    test('Delegates to strategy handler', () async {
      var result =
          await http.get('http://localhost:${server.port}/someDummyPath');
      expect(result.body, equals('some dummy response'));
    });
  });

  group('InjectedHandlerWithExtension', () {
    setUp(() async {
      var extensionUri = 'http://localhost:4000';
      var pipeline = const Pipeline().addMiddleware(
          createInjectedHandler(loadStrategy, extensionUri: extensionUri));
      server = await shelf_io.serve(pipeline.addHandler((request) {
        return Response.ok(
            '$entrypointExtensionMarker\n'
            '$mainExtensionMarker\n'
            'app.main.main()',
            headers: {HttpHeaders.etagHeader: entryEtag});
      }), 'localhost', 0);
    });

    tearDown(() async {
      await server.close();
    });

    test('Injects the extension backend port', () async {
      var result = await http.get(
          'http://localhost:${server.port}/entrypoint$bootstrapJsExtension');
      expect(result.body.contains('dartExtensionUri'), isTrue);
    });
  });
}
