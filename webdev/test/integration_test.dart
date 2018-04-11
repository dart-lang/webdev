// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'test_utils.dart';

void main() {
  test('non-existant commands create errors', () async {
    var process = await runWebDev(['monkey']);

    await expectLater(
        process.stdout, emits('Could not find a command named "monkey".'));

    await process.shouldExit(64);
  });

  var invalidRanges = <String, List<String>>{
    'build_runner': ['0.7.13+1', '0.9.0'],
    'build_web_compilers': ['0.3.5', '0.4.0']
  };

  for (var command in ['build', 'serve']) {
    group('`$command` command', () {
      group('missing dependency on', () {
        test('`build_runner` should fail', () async {
          await d.file('pubspec.yaml', '''
name: sample
''').create();

          await d
              .file('pubspec.lock', _pubspecLock(runnerVersion: null))
              .create();

          await d.file('.packages', '''
''').create();

          var process = await runWebDev([command], workingDirectory: d.sandbox);

          await checkProcessStdout(process, [
            r'''webdev could not run for this project.
You must have a dependency on `build_runner` in `pubspec.yaml`.'''
          ]);
          await process.shouldExit(78);
        });

        test('`build_web_compilers` should fail', () async {
          await d.file('pubspec.yaml', '''
name: sample
''').create();

          await d
              .file('pubspec.lock', _pubspecLock(webCompilersVersion: null))
              .create();

          await d.file('.packages', '''
''').create();

          var process = await runWebDev(['serve'], workingDirectory: d.sandbox);

          await checkProcessStdout(process, [
            r'''webdev could not run for this project.
You must have a dependency on `build_web_compilers` in `pubspec.yaml`.'''
          ]);
          await process.shouldExit(78);
        });

        test(
            '`build_web_compilers` should be ignored with '
            '--no-build-web-compilers', () async {
          await d.file('pubspec.yaml', '''
name: sample
''').create();

          await d
              .file('pubspec.lock', _pubspecLock(webCompilersVersion: null))
              .create();

          await d.file('.packages', '''
''').create();

          var process = await runWebDev(['serve', '--no-build-web-compilers'],
              workingDirectory: d.sandbox);

          // Fails w/ an isolate exception instead - since this is a fake package
          await checkProcessStdout(process, [
            'webdev failed with an unexpected exception.',
            // The isolate will fail - broken .packages file
            'Unable to spawn isolate'
          ]);
          await process.shouldExit(70);
        });
      });

      for (var entry in invalidRanges.entries) {
        group('with package `${entry.key}`', () {
          for (var version in entry.value) {
            test('at invalid version `$version` should fail', () async {
              var buildRunnerVersion = _supportedBuildRunnerVersion;
              var webCompilersVersion = _supportedWebCompilersVersion;

              String supportedRange;
              if (entry.key == 'build_runner') {
                buildRunnerVersion = version;
                supportedRange = '^0.8.2';
              } else {
                assert(entry.key == 'build_web_compilers');
                webCompilersVersion = version;
                supportedRange = '^0.3.6';
              }

              await d.file('pubspec.yaml', '''
name: sample
''').create();

              await d
                  .file(
                      'pubspec.lock',
                      _pubspecLock(
                          runnerVersion: buildRunnerVersion,
                          webCompilersVersion: webCompilersVersion))
                  .create();

              await d.file('.packages', '''
''').create();

              var process =
                  await runWebDev(['serve'], workingDirectory: d.sandbox);

              await checkProcessStdout(process, [
                'webdev could not run for this project.',
                // See https://github.com/dart-lang/linter/issues/965
                // ignore: prefer_adjacent_string_concatenation
                'The `${entry.key}` version – $version – ' +
                    'is not within the allowed constraint – $supportedRange.'
              ]);
              await process.shouldExit(78);
            });
          }
        });
      }

      test('no pubspec.yaml', () async {
        var process = await runWebDev(['serve'], workingDirectory: d.sandbox);

        await checkProcessStdout(process, [
          'webdev could not run for this project.',
          'Could not find a file named "pubspec.yaml"'
        ]);
        await process.shouldExit(78);
      });

      test('pubspec.yaml, no pubspec.lock', () async {
        await d.file('pubspec.yaml', '''
name: sample
''').create();

        var process = await runWebDev(['serve'], workingDirectory: d.sandbox);

        await checkProcessStdout(process, [
          'webdev could not run for this project.',
          'No pubspec.lock file found, please run "pub get" first.'
        ]);
        await process.shouldExit(78);
      });

      test('pubspec.yaml, pubspec.lock, no .packages', () async {
        await d.file('pubspec.yaml', '''
name: sample
''').create();

        await d.file('pubspec.lock', _pubspecLock()).create();

        var process = await runWebDev(['serve'], workingDirectory: d.sandbox);

        await checkProcessStdout(process, [
          'webdev could not run for this project.',
          'No .packages file found, please run "pub get" first.'
        ]);
        await process.shouldExit(78);
      });

      test('should fail gracefully if there is an isolate error', () async {
        await d.file('pubspec.yaml', '''
name: sample
''').create();

        await d.file('pubspec.lock', _pubspecLock()).create();

        await d.file('.packages', '').create();

        var process = await runWebDev(['serve'], workingDirectory: d.sandbox);

        await checkProcessStdout(process, [
          'webdev failed with an unexpected exception.',
          // The isolate will fail - broken .packages file
          'Unable to spawn isolate'
        ]);
        await process.shouldExit(70);
      });

      test('should fail if there has been a dependency change', () async {
        await d.file('pubspec.lock', _pubspecLock()).create();

        await d.file('.packages', '').create();

        // Ensure there is a noticeable delta in the creation times
        await new Future.delayed(const Duration(milliseconds: 1100));

        await d.file('pubspec.yaml', '''
name: sample
dependencies:
  args: ^1.0.0
''').create();

        var process = await runWebDev(['serve'], workingDirectory: d.sandbox);

        await checkProcessStdout(process, [
          'webdev could not run for this project.',
          // See https://github.com/dart-lang/linter/issues/965
          // ignore: prefer_adjacent_string_concatenation
          'The pubspec.yaml file has changed since the pubspec.lock file ' +
              'was generated, please run "pub get" again.'
        ]);
        await process.shouldExit(78);
      });
    });
  }
}

const _supportedBuildRunnerVersion = '0.8.2';
const _supportedWebCompilersVersion = '0.3.6';

String _pubspecLock(
    {String runnerVersion: _supportedBuildRunnerVersion,
    String webCompilersVersion: _supportedWebCompilersVersion}) {
  var buffer = new StringBuffer('''
# Copy-pasted from a valid run
packages:
''');

  if (runnerVersion != null) {
    buffer.writeln('''
  build_runner:
    dependency: "direct dev"
    description:
      name: build_runner
      url: "https://pub.dartlang.org"
    source: hosted
    version: "$runnerVersion"
''');
  }

  if (webCompilersVersion != null) {
    buffer.writeln('''
  build_web_compilers:
    dependency: "direct dev"
    description:
      name: build_web_compilers
      url: "https://pub.dartlang.org"
    source: hosted
    version: "$webCompilersVersion"
''');
  }

  return buffer.toString();
}
