// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 1))
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
  final _fixturesPath = p.absolute(p.join(p.current, '..', 'fixtures'));
  final _tempAppPath = p.join(_fixturesPath, 'temp_app');
  final _tempAppDir = Directory(_tempAppPath);

  setUp(() async {
    await Process.run(
      'dart',
      ['pub', 'global', 'deactivate', 'webdev'],
    );
    if (_tempAppDir.existsSync()) {
      await _tempAppDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    final serveProcess = _serveProcess;
    if (serveProcess != null) {
      Process.killPid(serveProcess.pid);
      _serveProcess = null;
    }
    if (_tempAppDir.existsSync()) {
      await _tempAppDir.delete(recursive: true);
    }
  });

  test('can activate and serve webdev', () async {
    // Verify that we can create a new Dart app:
    final createProcess = await Process.run(
      'dart',
      ['create', '--template', 'web', 'temp_app'],
      workingDirectory: _fixturesPath,
    );
    final createStderr = stringifyOutput(await createProcess.stderr);
    expect(createStderr, isEmpty);
    final createStdout = stringifyOutput(await createProcess.stdout);
    expect(createStdout, contains('Created project temp_app in temp_app!'));
    expect(await _tempAppDir.exists(), isTrue);
    // Verify that `dart pub global activate` works:
    final activateProcess = await Process.run(
      'dart',
      ['pub', 'global', 'activate', 'webdev'],
    );
    final activateStderr = stringifyOutput(await activateProcess.stderr);
    expect(activateStderr, isEmpty);
    final activateStdout = stringifyOutput(await activateProcess.stdout);
    expect(activateStdout, contains('Activated webdev'));
    // Verify that `webdev serve` works for our new app:
    _serveProcess = await Process.start(
        'dart', ['pub', 'global', 'run', 'webdev', 'serve'],
        workingDirectory: _tempAppPath);
    await expectLater(
        _serveProcess!.stdout.transform(utf8.decoder),
        emitsThrough(
          contains('Serving `web` on'),
        ));
    // Print any stderr logs from `webdev serve`:
    final serveStderr = stringifyOutput(
        await _serveProcess!.stderr.transform(utf8.decoder).toList());
    Logger.root.warning(serveStderr);
  });
}

String stringifyOutput(dynamic output) {
  if (output == null) return '';
  if (output == String) return output as String;
  final outputList = output is List ? output : [output];
  return outputList.map((output) => '$output').join('\n');
}
