// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/serve/utils.dart';
import 'package:webdev/src/util.dart';

import 'test_utils.dart';

/// Key: name of file in web directory
/// Value: `null`  - exists in both modes
///        `true`  - DDC only
///        `false` - dart2js only
const _testItems = <String, bool>{
  'main.dart.js': null,
  'main.dart.bootstrap.js': true,
  'main.ddc.js': true
};

void main() {
  String exampleDirectory;
  setUpAll(() async {
    exampleDirectory = p.absolute(p.join(p.current, '..', 'example'));

    var process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: exampleDirectory, environment: getPubEnvironment());

    await process.shouldExit(0);

    await d.file('.packages', isNotEmpty).validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);
  });

  test('build should fail if targetting an existing directory', () async {
    await d.file('simple thing', 'throw-away').create();

    var args = ['build', '-o', 'web:${d.sandbox}'];

    var process = await runWebDev(args, workingDirectory: exampleDirectory);

    // NOTE: We'd like this to be more useful
    // See https://github.com/dart-lang/build/issues/1283

    await expectLater(
        process.stdout,
        emitsThrough(
            '[SEVERE] Unable to create merged directory at ${d.sandbox}.'));
    await expectLater(
        process.stdout,
        emitsThrough(
            'Choose a different directory or delete the contents of that '
            'directory.'));

    await process.shouldExit(73);
  });

  group('should build with valid configuration', () {
    for (var withDDC in [true, false]) {
      test(withDDC ? 'DDC' : 'dart2js', () async {
        var args = ['build', '-o', 'web:${d.sandbox}'];
        if (withDDC) {
          args.add('--no-release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var expectedItems = <Object>['[INFO] Succeeded'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        for (var entry in _testItems.entries) {
          var shouldExist = (entry.value ?? withDDC) == withDDC;

          if (shouldExist) {
            await d.file(entry.key, isNotEmpty).validate();
          } else {
            await d.nothing(entry.key).validate();
          }
        }
      });
    }
  });

  group('should serve with valid configuration', () {
    for (var withDDC in [true, false]) {
      var type = withDDC ? 'DDC' : 'dart2js';
      test('using $type', () async {
        var openPort = await findUnusedPort();
        var args = ['serve', 'web:$openPort'];
        if (!withDDC) {
          args.add('--release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var hostUrl = 'http://localhost:$openPort';

        // Wait for the initial build to finish.
        await expectLater(process.stdout, emitsThrough(contains('Succeeded')));

        var client = HttpClient();

        try {
          for (var entry in _testItems.entries) {
            var url = Uri.parse('$hostUrl/${entry.key}');

            var request = await client.getUrl(url);
            var response = await request.close();

            var shouldExist = (entry.value ?? withDDC) == withDDC;

            expect(response.statusCode, shouldExist ? 200 : 404,
                reason: 'Expecting "$url"? $shouldExist');
          }
        } finally {
          client.close(force: true);
        }

        await process.kill();
        await process.shouldExit();
      });
    }
  });
}
