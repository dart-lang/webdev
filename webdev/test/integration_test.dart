// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';

final _webdevBin = p.absolute(p.join('bin', 'webdev.dart'));

Future<TestProcess> _runWebDev(List<String> args, {String workingDirectory}) {
  var fullArgs = [_webdevBin]..addAll(args);

  return TestProcess.start(dartPath, fullArgs,
      workingDirectory: workingDirectory);
}

void main() {
  test('README contains help output', () async {
    var process = await _runWebDev([]);
    var output = (await process.stdoutStream().join('\n')).trim();
    await process.shouldExit(0);

    var readme = new File('README.md');
    expect(readme.readAsStringSync(),
        contains('```console\n\$ webdev\n$output\n```'));
  });

  test('non-existant commands create errors', () async {
    var process = await _runWebDev(['monkey']);

    await expectLater(
        process.stdout, emits('Could not find a command named "monkey".'));

    await process.shouldExit(64);
  });

  test('should fail in a package without a build_runner dependency', () async {
    // Running on the `webdev` package directory – which has no dependency on
    // build runner.
    var process = await _runWebDev(['build']);
    var output = (await process.stdoutStream().join('\n')).trim();

    expect(output, contains(r'''Could not run in the current directory.
A dependency on `build_runner` was not found.'''));
    await process.shouldExit(78);
  });

  group('should fail when `build_runner` is the wrong version', () {
    for (var version in ['0.7.13+1', '0.9.0']) {
      test(version, () async {
        await d.file('pubspec.yaml', '''
name: sample
''').create();

        await d.file('pubspec.lock', '''
# Copy-pasted from a valid run
packages:
  build_runner:
    dependency: "direct main"
    description:
      name: build_runner
      url: "https://pub.dartlang.org"
    source: hosted
    version: "$version"
''').create();

        await d.file('.packages', '''
''').create();

        var process = await _runWebDev(['build'], workingDirectory: d.sandbox);

        await expectLater(
            process.stdout, emits('Could not run in the current directory.'));
        await expectLater(
            process.stdout,
            emits('The `build_runner` version – $version – '
                'is not within the supported range – >=0.8.0 <0.9.0.'));
        await process.shouldExit(78);
      });
    }
  });

  test('no pubspec.yaml', () async {
    var process = await _runWebDev(['build'], workingDirectory: d.sandbox);

    var output = await process.stdoutStream().join('\n');

    expect(output, contains('Could not run in the current directory.'));
    expect(output, contains('Could not find a file named "pubspec.yaml"'));
    await process.shouldExit(78);
  });

  test('pubspec.yaml, no pubspec.lock', () async {
    await d.file('pubspec.yaml', '''
name: sample
''').create();

    var process = await _runWebDev(['build'], workingDirectory: d.sandbox);

    var output = await process.stdoutStream().join('\n');

    expect(output, contains('Could not run in the current directory.'));
    expect(output,
        contains('No pubspec.lock file found, please run "pub get" first.'));
    await process.shouldExit(78);
  });

  test('pubspec.yaml, pubspec.lock, no .packages', () async {
    await d.file('pubspec.yaml', '''
name: sample
''').create();

    await d.file('pubspec.lock', '''
# Copy-pasted from a valid run
packages:
  build_runner:
    dependency: "direct main"
    description:
      name: build_runner
      url: "https://pub.dartlang.org"
    source: hosted
    version: "0.8.0"
''').create();

    var process = await _runWebDev(['build'], workingDirectory: d.sandbox);

    var output = await process.stdoutStream().join('\n');

    expect(output, contains('Could not run in the current directory.'));
    expect(output,
        contains('No .packages file found, please run "pub get" first.'));
    await process.shouldExit(78);
  });

  test('should fail gracefully if there is an isolate error', () async {
    await d.file('pubspec.yaml', '''
name: sample
''').create();

    await d.file('pubspec.lock', '''
# Copy-pasted from a valid run
packages:
  build_runner:
    dependency: "direct main"
    description:
      name: build_runner
      url: "https://pub.dartlang.org"
    source: hosted
    version: "0.8.0"
''').create();

    await d.file('.packages', '').create();

    var process = await _runWebDev(['build'], workingDirectory: d.sandbox);

    var output = await process.stdoutStream().join('\n');

    expect(output, contains('An unexpected exception has occurred.'));

    // The isolate will fail - broken .packages file
    expect(output, contains('Unable to spawn isolate'));
    await process.shouldExit(70);
  });

  test('should fail if there has been a dependency change', () async {
    await d.file('pubspec.lock', '''
# Copy-pasted from a valid run
packages:
  build_runner:
    dependency: "direct main"
    description:
      name: build_runner
      url: "https://pub.dartlang.org"
    source: hosted
    version: "0.8.0"
''').create();

    await d.file('.packages', '').create();

    // Ensure there is a noticeable delta in the creation times
    await new Future.delayed(const Duration(milliseconds: 500));

    await d.file('pubspec.yaml', '''
name: sample
dependencies:
  args: ^1.0.0
''').create();

    var process = await _runWebDev(['build'], workingDirectory: d.sandbox);

    var output = await process.stdoutStream().join('\n');

    expect(output, contains('Could not run in the current directory.'));
    expect(
        output,
        contains(
            'The pubspec.yaml file has changed since the pubspec.lock file '
            'was generated, please run "pub get" again.'));
    await process.shouldExit(78);
  });

  test('should succeed with valid configuration', () async {
    var exampleDirectory = p.absolute(p.join(p.current, '..', 'example'));
    var process = await TestProcess.start(pubPath, ['get'],
        workingDirectory: exampleDirectory, environment: _getPubEnvironment());

    await process.shouldExit(0);

    await d.file('.packages', isNotEmpty).validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);

    process = await _runWebDev(['build', '-o', d.sandbox],
        workingDirectory: exampleDirectory);

    var output = await process.stdoutStream().join('\n');

    expect(output, contains(d.sandbox));
    expect(output, contains('[INFO] Succeeded'));
    await process.shouldExit(0);

    await d.file('web/main.dart.js', isNotEmpty).validate();
  }, timeout: const Timeout(const Duration(minutes: 5)));
}

/// Returns an environment map that includes `PUB_ENVIRONMENT`.
///
/// Maintains any existing values for this environment var.
/// Adds a new value that flags this is a bot/test and not human usage.
Map<String, String> _getPubEnvironment() {
  var pubEnvironmentKey = 'PUB_ENVIRONMENT';
  var pubEnvironment = Platform.environment[pubEnvironmentKey] ?? '';
  if (pubEnvironment.isNotEmpty) {
    pubEnvironment = '$pubEnvironment;';
  }
  pubEnvironment = '${pubEnvironment}bot.pkg.webdev.test';

  var environment = {'PUB_ENVIRONMENT': pubEnvironment};

  return environment;
}
