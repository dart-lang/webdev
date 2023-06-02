// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(seconds: 90))
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// TODO(elliette): Move to a cron job. This tests that the currently published
// Webdev can be activated and serve a web app. It is intended to catch any
// regressions due to changes in the Dart SDK.

const timeoutDuration = Duration(seconds: 30);

void main() {
  Process? _serveProcess;
  Directory? _tempDir;

  Future<void> _expectStdoutAndCleanExit(Process process,
      {required String expectedStdout}) async {
    final stdoutCompleter = _captureStream(
      process.stdout,
      streamClosed: process.exitCode,
    );
    final stderrCompleter = _captureStream(
      process.stderr,
      streamClosed: process.exitCode,
    );
    final exitCode = await _waitForExitOrTimeout(process);
    final stderrLogs = await stderrCompleter.future;
    final stdoutLogs = await stdoutCompleter.future;
    // Log the stderr and stdout for debugging purposes if the process did not
    // terminate succesfully:
    if (exitCode != 0) {
      Logger.root.info('stderr: $stderrLogs');
      Logger.root.info('stdout: $stdoutLogs');
    }
    expect(exitCode, equals(0));
    expect(stderrLogs, isEmpty);
    expect(stdoutLogs, contains(expectedStdout));
  }

  Future<void> _expectStdoutThenExit(Process process,
      {required String expectedStdout}) async {
    final stdoutCompleter = _waitForStdoutOrTimeout(
      process,
      expectedStdout: expectedStdout,
    );
    expect(await stdoutCompleter.future, isTrue);
  }

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
      _serveProcess = null;
    }
  });

  test('can activate and serve webdev', () async {
    final tempDir = _tempDir!;
    final tempPath = tempDir.path;

    // Verify that we can create a new Dart app:
    final createProcess = await Process.start(
      'dart',
      ['create', '--template', 'web', 'temp_app'],
      workingDirectory: tempPath,
    );
    await _expectStdoutAndCleanExit(
      createProcess,
      expectedStdout: 'Created project temp_app in temp_app!',
    );
    final appPath = p.join(tempPath, 'temp_app');
    expect(await Directory(appPath).exists(), isTrue);

    // Verify that `dart pub global activate` works:
    final activateProcess = await Process.start(
      'dart',
      ['pub', 'global', 'activate', 'webdev'],
    );
    await _expectStdoutAndCleanExit(
      activateProcess,
      expectedStdout: 'Activated webdev',
    );

    // Verify that `webdev serve` works for our new app:
    _serveProcess = await Process.start(
        'dart', ['pub', 'global', 'run', 'webdev', 'serve'],
        workingDirectory: appPath);
    await _expectStdoutThenExit(_serveProcess!,
        expectedStdout: 'Serving `web` on');
  });
}

Future<int> _waitForExitOrTimeout(Process process) {
  Timer(timeoutDuration, () {
    Logger.root.severe('Process timed out after $timeoutDuration');
    process.kill();
  });
  return process.exitCode;
}

Completer<bool> _waitForStdoutOrTimeout(Process process,
    {required String expectedStdout}) {
  final completer = Completer<bool>();
  var stdoutLogs = '';
  var stderrLogs = '';

  Timer(timeoutDuration, () {
    Logger.root.severe(
        'Waiting for "$expectedStdout" timed out after $timeoutDuration');
    Logger.root.info('stdout: $stdoutLogs');
    Logger.root.info('stderr: $stderrLogs');
    process.kill();
    completer.complete(false);
  });

  process.stderr.transform(utf8.decoder).listen((line) {
    stderrLogs += line;
  });
  process.stdout.transform(utf8.decoder).listen((line) {
    if (line.contains(expectedStdout)) {
      process.kill();
      completer.complete(true);
    }
  });

  return completer;
}

Completer<String> _captureStream(
  Stream<List<int>> stream, {
  required Future<int> streamClosed,
}) {
  final completer = Completer<String>();
  var output = '';
  stream.transform(utf8.decoder).listen((line) {
    output += line;
  });
  unawaited(streamClosed.then((_) => completer.complete(output)));
  return completer;
}
