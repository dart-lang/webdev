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
  Process? createProcess;
  Process? activateProcess;
  Process? serveProcess;
  Directory? tempDir0;

  final testScript =
      File(p.join(p.dirname(Platform.script.toFilePath()), 'test.dart'))
          .readAsStringSync();
  final thisScript = File.fromUri(Uri.parse(testScript.substring(
      testScript.lastIndexOf('import', testScript.indexOf('as test;')) + 8,
      testScript.indexOf('as test;') - 2)));
  final packageDir = p.dirname(p.dirname(thisScript.path));

  Future<void> expectStdoutAndCleanExit(Process process,
      {required String expectedStdout}) async {
    final stdoutCompleter = _captureOutput(
      process,
      streamType: StreamType.stdout,
      stopCaptureFuture: process.exitCode,
    );
    final stderrCompleter = _captureOutput(
      process,
      streamType: StreamType.stderr,
      stopCaptureFuture: process.exitCode,
    );
    final exitCode = await _waitForExitOrTimeout(process);
    final stderrLogs = await stderrCompleter.future;
    final stdoutLogs = await stdoutCompleter.future;
    expect(
      exitCode,
      equals(0),
      // Include the stderr and stdout logs if the process does not terminate
      // cleanly:
      reason: 'stderr: $stderrLogs, stdout: $stdoutLogs',
    );
    expect(
      stderrLogs,
      isEmpty,
    );
    expect(
      stdoutLogs,
      contains(expectedStdout),
    );
  }

  Future<void> expectStdoutThenExit(Process process,
      {required String expectedStdout}) async {
    final expectedStdoutCompleter = _waitForStdoutOrTimeout(
      process,
      expectedStdout: expectedStdout,
    );
    final stderrCompleter = _captureOutput(
      process,
      streamType: StreamType.stderr,
      stopCaptureFuture: expectedStdoutCompleter.future,
    );
    final stdoutLogs = await expectedStdoutCompleter.future;
    final stderrLogs = await stderrCompleter.future;
    expect(
      stdoutLogs, contains(expectedStdout),
      // Also include the stderr if the stdout is not expected.
      reason: 'stderr: $stderrLogs',
    );
  }

  setUp(() async {
    tempDir0 = Directory.systemTemp.createTempSync('installation_test');

    await Process.run(
      'dart',
      ['pub', 'global', 'deactivate', 'webdev'],
    );
  });

  tearDown(() async {
    // Kill any stale processes:
    if (createProcess != null) {
      Process.killPid(createProcess!.pid, ProcessSignal.sigint);
      createProcess = null;
    }
    if (activateProcess != null) {
      Process.killPid(activateProcess!.pid, ProcessSignal.sigint);
      activateProcess = null;
    }
    if (serveProcess != null) {
      Process.killPid(serveProcess!.pid, ProcessSignal.sigint);
      serveProcess = null;
    }
  });

  test('can activate and serve webdev', () async {
    final tempDir = tempDir0!;
    final tempPath = tempDir.path;

    // Verify that we can create a new Dart app:
    createProcess = await Process.start(
      'dart',
      ['create', '--template', 'web', 'temp_app'],
      workingDirectory: tempPath,
    );
    await expectStdoutAndCleanExit(
      createProcess!,
      expectedStdout: 'Created project temp_app in temp_app!',
    );
    final appPath = p.join(tempPath, 'temp_app');
    expect(await Directory(appPath).exists(), isTrue);

    // Verify that `dart pub global activate` works:
    activateProcess = await Process.start(
      'dart',
      ['pub', 'global', 'activate', 'webdev'],
    );
    await expectStdoutAndCleanExit(
      activateProcess!,
      expectedStdout: 'Activated webdev',
    );

    // Verify that `webdev serve` works for our new app:
    serveProcess = await Process.start(
        'dart', ['pub', 'global', 'run', 'webdev', 'serve'],
        workingDirectory: appPath);
    await expectStdoutThenExit(serveProcess!,
        expectedStdout: 'Serving `web` on');
  });

  test('activate and serve webdev fails with offline', () async {
    final tempDir = tempDir0!;
    final tempPath = tempDir.path;

    // Verify that we can create a new Dart app:
    createProcess = await Process.start(
      'dart',
      ['create', '--no-pub', '--template', 'web', 'temp_app'],
      workingDirectory: tempPath,
    );
    await expectStdoutAndCleanExit(
      createProcess!,
      expectedStdout: 'Created project temp_app in temp_app!',
    );
    final appPath = p.join(tempPath, 'temp_app');
    expect(await Directory(appPath).exists(), isTrue);

    // Verify that `dart pub global activate` works:
    activateProcess = await Process.start(
      'dart',
      ['pub', 'global', 'activate', '--source', 'path', packageDir],
    );
    await expectStdoutAndCleanExit(
      activateProcess!,
      expectedStdout: 'Activated webdev',
    );

    // Verify that `webdev serve` works for our new app:
    serveProcess = await Process.start('dart',
        ['pub', 'global', 'run', 'webdev', 'serve', '--offline', 'web:8081'],
        workingDirectory: appPath);
    await expectStdoutThenExit(serveProcess!,
        expectedStdout: 'Cannot open file\n  pubspec.lock\n');
  });
}

Future<int> _waitForExitOrTimeout(Process process) {
  Timer(processTimeout, () {
    process.kill(ProcessSignal.sigint);
  });
  return process.exitCode;
}

/// Returns the stdout for the [process] once the [expectedStdout] is found.
///
/// Otherwise returns all the stdout up to the [processTimeout].
Completer<String> _waitForStdoutOrTimeout(Process process,
    {required String expectedStdout}) {
  var output = '';
  final completer = Completer<String>();

  Timer(processTimeout, () {
    process.kill(ProcessSignal.sigint);
    if (!completer.isCompleted) {
      completer.complete(output);
    }
  });
  process.stdout.transform(utf8.decoder).listen((line) {
    output += line;
    if (line.contains(expectedStdout)) {
      process.kill(ProcessSignal.sigint);
      if (!completer.isCompleted) {
        completer.complete(output);
      }
    }
  });

  return completer;
}

Completer<String> _captureOutput(
  Process process, {
  required StreamType streamType,
  required Future stopCaptureFuture,
}) {
  final stream =
      streamType == StreamType.stdout ? process.stdout : process.stderr;
  final completer = Completer<String>();
  var output = '';
  stream.transform(utf8.decoder).listen((line) {
    output += line;
    if (line.contains('[SEVERE]')) {
      process.kill(ProcessSignal.sigint);
      if (!completer.isCompleted) {
        completer.complete(output);
      }
    }
  });
  unawaited(stopCaptureFuture.then((_) {
    if (!completer.isCompleted) {
      completer.complete(output);
    }
  }));
  return completer;
}
