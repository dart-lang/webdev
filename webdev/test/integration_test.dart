// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'test_utils.dart';

void main() {
  final testRunner = TestRunner();
  setUpAll(testRunner.setUpAll);
  tearDownAll(testRunner.tearDownAll);

  test('non-existent commands create errors', () async {
    final process = await testRunner.runWebDev(['monkey']);

    await expectLater(
        process.stdout, emits('Could not find a command named "monkey".'));

    await process.shouldExit(64);
  });

  test('passing extra args to build fails with bad usage', () async {
    final process = await testRunner.runWebDev(['build', 'extra', 'args']);

    await expectLater(process.stdout,
        emits('Arguments were provided that are not supported: "extra args".'));

    await process.shouldExit(64);
  });

  test('Errors with `build_runner` should not surface `build_daemon` issues',
      () async {
    await d.file('pubspec.yaml', _pubspecYaml).create();

    await d
        .file(
            'pubspec.lock',
            _pubspecLock(
              runnerVersion: '1.2.8',
              daemonVersion: '0.4.0',
            ))
        .create();

    await d.dir('.dart_tool', [d.file('package_config.json', '')]).create();
    await d.file('.dart_tool/package_config.json', '').create();

    final process =
        await testRunner.runWebDev(['serve'], workingDirectory: d.sandbox);

    final output = await process.stdout.rest.toList();

    expect(output, isNot(contains(contains('`build_daemon`'))));

    await process.shouldExit(78);
  });

  final invalidRanges = <String, List<String>>{
    'build_runner': ['0.8.9', '3.0.0'],
    'build_web_compilers': ['0.3.5', '5.0.0'],
    'build_daemon': ['0.3.0', '5.0.0'],
  };

  for (final command in ['build', 'serve', 'daemon']) {
    group('`$command` command', () {
      group('missing dependency on', () {
        test('`build_runner` should fail', () async {
          await d.file('pubspec.yaml', _pubspecYaml).create();

          await d
              .file('pubspec.lock', _pubspecLock(runnerVersion: null))
              .create();

          await d
              .dir('.dart_tool', [d.file('package_config.json', '')]).create();
          await d.file('.dart_tool/package_config.json', '').create();

          final process = await testRunner
              .runWebDev([command], workingDirectory: d.sandbox);

          await checkProcessStdout(process, ['webdev could not run']);
          await process.shouldExit(78);
        });

        test('`build_web_compilers` should fail', () async {
          await d.file('pubspec.yaml', _pubspecYaml).create();

          await d
              .file('pubspec.lock', _pubspecLock(webCompilersVersion: null))
              .create();

          await d
              .dir('.dart_tool', [d.file('package_config.json', '')]).create();
          await d.file('.dart_tool/package_config.json', '').create();

          final process = await testRunner
              .runWebDev(['serve'], workingDirectory: d.sandbox);

          await checkProcessStdout(process, ['webdev could not run']);
          await process.shouldExit(78);
        });

        test(
            '`build_web_compilers` should be ignored with '
            '--no-build-web-compilers', () async {
          await d.file('pubspec.yaml', _pubspecYaml).create();

          await d
              .file('pubspec.lock', _pubspecLock(webCompilersVersion: null))
              .create();

          await d
              .dir('.dart_tool', [d.file('package_config.json', '')]).create();
          await d.file('.dart_tool/package_config.json', '').create();

          // Required for webdev to not complain about nothing to serve.
          await d.dir('web').create();

          final process = await testRunner.runWebDev(
              ['serve', '--no-build-web-compilers'],
              workingDirectory: d.sandbox);

          await process.shouldExit();
        });
      });

      for (final entry in invalidRanges.entries) {
        group('with package `${entry.key}`', () {
          for (final version in entry.value) {
            test('at invalid version `$version` should fail', () async {
              var buildRunnerVersion = _supportedBuildRunnerVersion;
              var webCompilersVersion = _supportedWebCompilersVersion;
              var buildDaemonVersion = _supportedBuildDaemonVersion;

              switch (entry.key) {
                case 'build_runner':
                  buildRunnerVersion = version;
                  break;
                case 'build_web_compilers':
                  webCompilersVersion = version;
                  break;
                case 'build_daemon':
                  buildDaemonVersion = version;
              }

              await d.file('pubspec.yaml', _pubspecYaml).create();

              await d
                  .file(
                      'pubspec.lock',
                      _pubspecLock(
                          runnerVersion: buildRunnerVersion,
                          webCompilersVersion: webCompilersVersion,
                          daemonVersion: buildDaemonVersion))
                  .create();

              await d.dir(
                  '.dart_tool', [d.file('package_config.json', '')]).create();
              await d.file('.dart_tool/package_config.json', '').create();

              final process = await testRunner
                  .runWebDev(['serve'], workingDirectory: d.sandbox);

              await checkProcessStdout(process, ['webdev could not run']);

              await process.shouldExit(78);
            });
          }
        });
      }

      test('no pubspec.yaml', () async {
        final process =
            await testRunner.runWebDev(['serve'], workingDirectory: d.sandbox);

        await checkProcessStdout(process, ['webdev could not run']);
        await process.shouldExit(78);
      });

      test(
        'pubspec.yaml, no pubspec.lock',
        () async {
          await d.file('pubspec.yaml', _pubspecYaml).create();

          final process = await testRunner
              .runWebDev(['serve'], workingDirectory: d.sandbox);

          await checkProcessStdout(process, ['webdev could not run']);
          await process.shouldExit(78);
        },
      );

      test('should fail if there has been a dependency change', () async {
        await d.file('pubspec.lock', _pubspecLock()).create();

        await d.dir('.dart_tool', [d.file('package_config.json', '')]).create();
        await d.file('.dart_tool/package_config.json', '').create();

        // Ensure there is a noticeable delta in the creation times
        await Future.delayed(const Duration(milliseconds: 1100));

        await d.file('pubspec.yaml', '''
name: sample
dependencies:
  args: ^1.0.0
''').create();

        final process =
            await testRunner.runWebDev(['serve'], workingDirectory: d.sandbox);

        await checkProcessStdout(process, ['webdev could not run']);
        await process.shouldExit(78);
      });
    });
  }
}

const _supportedBuildRunnerVersion = '2.4.0';
const _supportedWebCompilersVersion = '4.0.4';
const _supportedBuildDaemonVersion = '4.0.0';

String _pubspecYaml = '''
  name: sample
''';

String _pubspecLock(
    {String? runnerVersion = _supportedBuildRunnerVersion,
    String? webCompilersVersion = _supportedWebCompilersVersion,
    String? daemonVersion = _supportedBuildDaemonVersion,
    List<String> extraPkgs = const []}) {
  final buffer = StringBuffer('''
# Copy-pasted from a valid run
packages:
''');

  if (runnerVersion != null) {
    buffer.writeln('''
  build_runner:
    dependency: "direct dev"
    description:
      name: build_runner
      url: "https://pub.dev"
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
      url: "https://pub.dev"
    source: hosted
    version: "$webCompilersVersion"
''');
  }

  if (daemonVersion != null) {
    buffer.writeln('''
  build_daemon:
    dependency: "direct transitive"
    description:
      name: build_daemon
      url: "https://pub.dev"
    source: hosted
    version: "$daemonVersion"
''');
  }

  for (final pkg in extraPkgs) {
    buffer.writeln('''
  $pkg:
    dependency: "direct"
    description:
      name: $pkg
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
''');
  }

  return buffer.toString();
}
