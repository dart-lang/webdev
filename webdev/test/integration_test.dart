// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  final testRunner = TestRunner();
  setUpAll(testRunner.setUpAll);
  tearDownAll(testRunner.tearDownAll);

  test('non-existent commands create errors', () async {
    final process = await testRunner.runWebDev(['monkey']);

    await expectLater(
        process.stdout, emits('Could not find a command named "monkey".'));

    await process.shouldExit(64);
  });

  test('passing extra args to build fails with bad usage', () async {
    final process = await testRunner.runWebDev(['build', 'extra', 'args']);

    await expectLater(process.stdout,
        emits('Arguments were provided that are not supported: "extra args".'));

    await process.shouldExit(64);
  });
}
