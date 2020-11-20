// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import 'fixtures/logging.dart';

@TestOn('vm')
void main() async {
  group('expression compiler service with fake asset server', () {
    ExpressionCompilerService service;
    var output = StreamController<String>.broadcast();
    HttpServer server;
    var systemTempDir = Directory.systemTemp;
    var outputDir = systemTempDir.createTempSync('foo bar');
    var source = p.join(outputDir.path, 'try.dart');
    var kernel = p.join(outputDir.path, 'try.full.dill');

    FutureOr<Response> assetHandler(Request request) {
      return Response(200, body: File(kernel).readAsBytesSync());
    }

    Future<void> stop() async {
      await service?.stop();
      await server?.close();
      await output?.close();
      service = null;
      server = null;
      output = null;
    }

    setUpAll(() async {
      // redirect logs for testing
      configureLogWriter(
          customLogWriter: (level, message,
                  {loggerName, error, stackTrace, verbose}) =>
              output.add('[$level] $loggerName: $message'));

      output.stream.listen(printOnFailure);

      // start expression compilation service
      var port = await findUnusedPort();
      service = await ExpressionCompilerService.start(
          'localhost', port, assetHandler, false);

      // setup asset server
      server = await HttpMultiServer.bind('localhost', port);
      shelf_io.serveRequests(server, service.handler);

      // generate full dill
      File(source).writeAsStringSync('''void main() {
        // breakpoint line
      }''');

      var process = await Process.start(
              p.join(p.dirname(Platform.resolvedExecutable), 'dartdevc'),
              [
                'try.dart',
                '-o',
                'try.js',
                '--experimental-output-compiled-kernel',
                '--multi-root',
                outputDir.path,
                '--multi-root-scheme',
                'org-dartlang-app',
              ],
              workingDirectory: outputDir.path)
          .then((p) {
        stdout.addStream(p.stdout);
        stderr.addStream(p.stderr);
        return p;
      });
      await process.exitCode;
    });

    tearDownAll(() async {
      await stop();
      outputDir.deleteSync(recursive: true);
    });

    test('works with no errors', () async {
      expect(output.stream, neverEmits(contains('[SEVERE]')));
      expect(
          output.stream,
          emitsThrough(contains(
              '[INFO] ExpressionCompilerService: Updating dependencies...')));
      expect(
          output.stream,
          emitsThrough(contains(
              '[INFO] ExpressionCompilerService: Updated dependencies.')));
      expect(
          output.stream,
          emitsThrough(contains(
              '[FINEST] ExpressionCompilerService: Compiling "true" at org-dartlang-app:/try.dart:2')));
      expect(
          output.stream,
          emitsThrough(contains(
              '[FINEST] ExpressionCompilerService: Compiled "true" to:')));

      var result = await service.updateDependencies({'try': 'try.full.dill'});
      expect(result, true);

      var compilationResult = await service.compileExpressionToJs(
          '0', 'org-dartlang-app:/try.dart', 2, 1, {}, {}, 'try', 'true');
      expect(compilationResult.result, contains('return true;'));
      expect(compilationResult.isError, false);

      await stop();
    });
  });
}
