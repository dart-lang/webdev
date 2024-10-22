// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// TODO(elliette): Move to a cron job. This tests that the currently published
// Webdev can be activated and serve a web app. It is intended to catch any
// regressions due to changes in the Dart SDK.

enum StreamType {
  stdout,
  stderr,
}

const processTimeout = Duration(minutes: 1);

void main() {
  test('can activate and serve webdev', () async {
    await withTempDir((tempDir) async {
      final tempPath = tempDir.path;

      await runCommand(
        Platform.resolvedExecutable,
        ['create', '--template', 'web', 'temp_app'],
        workingDirectory: tempPath,
        expectedStdout: 'Created project temp_app in temp_app!',
      );

      final appPath = p.join(tempPath, 'temp_app');
      expect(await Directory(appPath).exists(), isTrue);

      // Verify that `dart pub add dev:webdev` works:
      await runCommand(
        Platform.resolvedExecutable,
        ['pub', 'add', 'dev:webdev'],
        expectedStdout: '+ webdev',
        workingDirectory: appPath,
      );

      // Verify that `webdev serve` works for our new app:
      final serveProcess = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'webdev', 'serve'],
        workingDirectory: appPath,
      );
      try {
        serveProcess.stderr.listen((x) => print(utf8.decode(x)));
        await expectLater(serveProcess.stdout.transform(utf8.decoder),
            emitsThrough(contains('Serving `web` on')));
      } finally {
        serveProcess.kill();
      }
    });
  });
}

Future<void> runCommand(
  String executable,
  List<String> arguments, {
  required String expectedStdout,
  int expectedExit = 0,
  String? workingDirectory,
}) async {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  printOnFailure('Running `$executable ${arguments.join(' ')}`');
  printOnFailure(result.stderr);
  printOnFailure(result.stdout);
  expect(result.stdout, contains(expectedStdout));
  expect(result.stderr, isEmpty);
  expect(result.exitCode, expectedExit);
}

Future<T> withTempDir<T>(Future<T> Function(Directory tempDir) callback) async {
  final tempDir = Directory.systemTemp.createTempSync('installation_test');
  try {
    return await callback(tempDir);
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}
