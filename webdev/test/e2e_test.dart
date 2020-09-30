// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
import 'dart:io';

import 'package:io/io.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/pubspec.dart';
import 'package:webdev/src/serve/utils.dart';
import 'package:webdev/src/util.dart';
import 'package:yaml/yaml.dart';

import 'test_utils.dart';

/// Key: name of file in web directory
/// Value: `null`  - exists in both modes
///        `true`  - DDC only
///        `false` - dart2js only
const _testItems = <String, bool>{
  'main.dart.js': null,
  'main.dart.bootstrap.js': true,
  'main.unsound.ddc.js': true,
};

void main() {
  String exampleDirectory;
  setUpAll(() async {
    exampleDirectory =
        p.absolute(p.join(p.current, '..', 'fixtures', '_webdevSmoke'));

    var process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: exampleDirectory, environment: getPubEnvironment());

    await process.shouldExit(0);

    await d.file('.packages', isNotEmpty).validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);
  });

  test('smoke test is configured properly', () async {
    var smokeYaml =
        loadYaml(await File('$exampleDirectory/pubspec.yaml').readAsString())
            as YamlMap;
    var webdevYaml =
        loadYaml(await File('pubspec.yaml').readAsString()) as YamlMap;
    expect(smokeYaml['environment']['sdk'],
        equals(webdevYaml['environment']['sdk']));
    expect(smokeYaml['dev_dependencies']['build_runner'],
        equals(buildRunnerConstraint.toString()));
    expect(smokeYaml['dev_dependencies']['build_web_compilers'],
        equals(buildWebCompilersContraint.toString()));
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
            contains('Unable to create merged directory at ${d.sandbox}.')));
    await expectLater(
        process.stdout,
        emitsThrough(
            'Choose a different directory or delete the contents of that '
            'directory.'));

    await process.shouldExit(isNot(0));
  });

  test('build should allow passing extra arguments to build_runner', () async {
    var args = [
      'build',
      '-o',
      'web:${d.sandbox}',
      '--',
      '--delete-conflicting-outputs'
    ];

    var process = await runWebDev(args, workingDirectory: exampleDirectory);

    await checkProcessStdout(process, ['Succeeded']);
    await process.shouldExit(0);
  });

  group('should build with valid configuration', () {
    for (var withDDC in [true, false]) {
      test(withDDC ? 'DDC' : 'dart2js', () async {
        var args = ['build', '-o', 'web:${d.sandbox}'];
        if (withDDC) {
          args.add('--no-release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var expectedItems = <Object>['Succeeded'];

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

  group('should build with --output=NONE', () {
    for (var withDDC in [true, false]) {
      test(withDDC ? 'DDC' : 'dart2js', () async {
        var args = ['build', '--output=NONE'];
        if (withDDC) {
          args.add('--no-release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var expectedItems = <Object>['Succeeded'];

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        await d.nothing('build').validate(exampleDirectory);
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

  group('Should fail with invalid build directories', () {
    var invalidServeDirs = ['.', '../', '../foo', 'foo/bar', 'foo/../'];
    for (var dir in invalidServeDirs) {
      for (var command in ['build', 'serve']) {
        test('cannot $command directory: `$dir`', () async {
          var args = [
            command,
            if (command == 'build') '--output=$dir:foo' else dir
          ];

          var process =
              await runWebDev(args, workingDirectory: exampleDirectory);
          await expectLater(
              process.stdout,
              emitsThrough(contains(
                  'Invalid configuration: Only top level directories under the '
                  'package can be built')));
          await expectLater(process.exitCode, completion(ExitCode.config.code));
        });
      }
    }
  });
}
