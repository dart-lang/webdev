// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

import 'test_utils.dart';

void main() {
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

  for (final moduleFormat in [ModuleFormat.amd, ModuleFormat.ddc]) {
    group('Module Format ${moduleFormat.name} |', () {
      late TestRunner testRunner;

      setUpAll(() async {
        testRunner = TestRunner(
          ddcModuleFormat: moduleFormat,
          canaryFeatures: moduleFormat == ModuleFormat.ddc,
        );
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
          if (moduleFormat == ModuleFormat.ddc) ...[
            '--module-format',
            'ddc',
            '--canary',
          ],
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
}
