// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(seconds: 90))
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// TODO(elliette): Move to a cron job. This tests that the currently published
// Webdev can be activated and serve a web app. It is intended to catch any
// regressions due to changes in the Dart SDK.
void main() {
  Process? _serveProcess;
  Directory? _tempDir;

  setUp(() async {
    _tempDir = Directory.systemTemp.createTempSync('installation_test');

    await Process.run(
      'dart',
      ['pub', 'global', 'deactivate', 'webdev'],
    );
  });

  tearDown(() async {
    final serveProcess = _serveProcess;
    if (serveProcess != null) {
      Process.killPid(serveProcess.pid);
      maybeLogStderr(serveProcess);
      _serveProcess = null;
    }
    final tempDir = _tempDir;
    if (tempDir != null && tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
      _tempDir = null;
    }
  });

  test('can activate and serve webdev', () async {
    final tempDir = _tempDir!;
    final tempPath = tempDir.path;
    // Verify that we can create a new Dart app:
    final createProcess = await Process.run(
      'dart',
      ['create', '--template', 'web', 'temp_app'],
      workingDirectory: tempPath,
    );
    final createStderr = stringifyOutput(await createProcess.stderr);
    expect(createStderr, isEmpty);
    final createStdout = stringifyOutput(await createProcess.stdout);
    expect(createStdout, contains('Created project temp_app in temp_app!'));
    expect(createProcess.exitCode, equals(0));
    final appPath = p.join(tempPath, 'temp_app');
    expect(await Directory(appPath).exists(), isTrue);
    // Verify that `dart pub global activate` works:
    final activateProcess = await Process.run(
      'dart',
      ['pub', 'global', 'activate', 'webdev'],
    );
    final activateStderr = stringifyOutput(await activateProcess.stderr);
    expect(activateStderr, isEmpty);
    final activateStdout = stringifyOutput(await activateProcess.stdout);
    expect(activateStdout, contains('Activated webdev'));
    expect(activateProcess.exitCode, equals(0));
    // Verify that `webdev serve` works for our new app:
    _serveProcess = await Process.start(
        'dart', ['pub', 'global', 'run', 'webdev', 'serve'],
        workingDirectory: appPath);
    final serveStdout = _serveProcess!.stdout.transform(utf8.decoder);
    await expectLater(serveStdout, emitsThrough(contains('Serving `web` on')));
  });
}

String stringifyOutput(dynamic output) {
  if (output == null) return '';
  if (output == String) return output as String;
  final outputList = output is List ? output : [output];
  return outputList.map((output) => '$output').join('\n');
}

void maybeLogStderr(Process process) async {
  final stderr = stringifyOutput(
    await process.stderr.transform(utf8.decoder).toList(),
  );
  if (stderr.isNotEmpty) {
    Logger.root.warning('stderr:');
    Logger.root.warning(stderr);
  }
}
