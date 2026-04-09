// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'test_utils.dart';

void main() {
  final testRunner = TestRunner();
  late String webdevAotPath;

  setUpAll(() async {
    await testRunner.setUpAll();

    final webdevScriptPath = p.join(p.current, 'bin', 'webdev.dart');
    webdevAotPath = p.join(p.current, 'test', 'webdev.exe');

    final process = await Process.run(testRunner.sdkLayout.dartPath, [
      'compile',
      'exe',
      webdevScriptPath,
      '-o',
      webdevAotPath,
    ]);

    if (process.exitCode != 0) {
      fail('Failed to compile webdev to AOT: ${process.stderr}');
    }
  });

  tearDownAll(() async {
    testRunner.tearDownAll();
    final webdevAotFile = File(webdevAotPath);
    if (await webdevAotFile.exists()) {
      await webdevAotFile.delete();
    }
  });

  test('webdev serve can run in AOT mode', () async {
    final exampleDirectory = await testRunner.prepareWorkspace();

    final process = await TestProcess.start(webdevAotPath, [
      'serve',
      '--debug',
      '--no-launch-in-chrome',
      '--chrome-debug-port=9222',
    ], workingDirectory: exampleDirectory);

    await expectLater(
      process.stdout,
      emitsThrough(contains('Serving `web` on')),
    );

    await process.kill();
    await process.shouldExit();
  });
}
