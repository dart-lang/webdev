// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

void main() {
  test('README contains help output', () async {
    var process = await TestProcess.start('dart', ['bin/webdev.dart']);

    var output = (await process.stdoutStream().join('\n')).trim();

    var readme = new File('README.md');

    expect(readme.readAsStringSync(),
        contains('```console\n\$ webdev\n$output\n```'));

    await process.shouldExit(0);
  });

  test('non-existant commands create errors', () async {
    var process =
        await TestProcess.start('dart', ['bin/webdev.dart', 'monkey']);

    var output = (await process.stdoutStream().join('\n')).trim();

    expect(output, contains('Could not find a command named "monkey".'));

    await process.shouldExit(64);
  });

  test('should fail in a package without a build_runner dependency', () async {
    var process = await TestProcess.start('dart', ['bin/webdev.dart', 'serve']);
    await process.shouldExit(255);
  });
}
