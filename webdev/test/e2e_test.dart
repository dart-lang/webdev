// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(const Duration(minutes: 5))

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';

import 'test_utils.dart';

/// Key: name of file in web directory
/// Value: `null`  - exists in both modes
///        `true`  - DDC only
///        `false` - dart2js only
const _testItems = const <String, bool>{
  'main.dart.js': null,
  'main.dart.bootstrap.js': true,
  'main.ddc.js': true
};

void main() {
  String exampleDirectory;
  setUpAll(() async {
    exampleDirectory = p.absolute(p.join(p.current, '..', 'example'));

    var process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: exampleDirectory, environment: _getPubEnvironment());

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
            '[WARNING] Skipped creation of the merged output directory.'));

    await expectLater(
        process.stderr,
        emitsThrough(
            '[SEVERE] Unable to create merged directory for ${d.sandbox}.'));
    await expectLater(
        process.stderr,
        emitsThrough(
            'Choose a different directory or delete the contents of that '
            'directory.'));
    await expectLater(process.stderr,
        emitsThrough('Failed to create merged output directories.'));

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
      test(withDDC ? 'DDC' : 'dart2js', () async {
        var openPort = await _getOpenPort();
        var args = ['serve', 'web:$openPort'];
        if (!withDDC) {
          args.add('--release');
        }

        var process = await runWebDev(args, workingDirectory: exampleDirectory);

        var hostUrl = 'http://localhost:$openPort';

        await expectLater(
            process.stdout, emitsThrough('Serving `web` on $hostUrl'));

        var client = new HttpClient();

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

        if (Platform.isWindows) {
          await process.kill();
          await process.shouldExit(-1);
        } else {
          process.signal(ProcessSignal.sigint);
          await process.shouldExit(0);
        }
      });
    }
  });
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

/// Returns an open port by creating a temporary Socket
Future<int> _getOpenPort() async {
  ServerSocket socket;

  try {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  } catch (_) {
    // try again v/ V6 only. Slight possibility that V4 is disabled
    socket =
        await ServerSocket.bind(InternetAddress.loopbackIPv6, 0, v6Only: true);
  }

  try {
    return socket.port;
  } finally {
    await socket.close();
  }
}
