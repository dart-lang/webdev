// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

void webdevAotTests({
  required TestRunner testRunner,
  required List<String> serveArgs,
}) {
  // Initialize a base runner to retrieve the SDK path.
  final baseRunner = TestRunner();
  late String webdevAotPath;

  setUpAll(() async {
    await baseRunner.setUpAll();

    final webdevScriptPath = p.join(p.current, 'bin', 'webdev.dart');
    webdevAotPath = p.join(p.current, 'test', 'webdev.exe');

    final process = await Process.run(baseRunner.sdkLayout.dartPath, [
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
    baseRunner.tearDownAll();
    final webdevAotFile = File(webdevAotPath);
    if (await webdevAotFile.exists()) {
      await webdevAotFile.delete();
    }
  });

  group('Module Format ${testRunner.ddcModuleFormat.name} |', () {
    setUpAll(() async {
      await testRunner.setUpAll();
    });

    tearDownAll(() async {
      testRunner.tearDownAll();
    });

    test('webdev serve can run in AOT mode', () async {
      final exampleDirectory = await testRunner.prepareWorkspace();

      final process = await TestProcess.start(webdevAotPath, [
        'serve',
        '--debug',
        '--no-launch-in-chrome',
        '--chrome-debug-port=9222',
        ...serveArgs,
        'web:0',
      ], workingDirectory: exampleDirectory);

      await expectLater(
        process.stdout,
        emitsThrough(contains('Serving `web` on')),
      );

      await process.kill();
      await process.shouldExit();
    });
  });
}
