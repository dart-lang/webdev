// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
@Tags(['requires-edge-sdk'])

import 'package:test/test.dart';

import '../test_utils.dart';
import 'utils.dart';

void main() {
  String exampleDirectory;

  setUpAll(() async {
    exampleDirectory = await prepareWorkspace();
  });

  group('AppDomain', () {
    group('Events', () {
      test('.start', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emitsThrough(startsWith('[{"event":"app.start"')));
        await exitWebdev(webdev);
      });

      test('.started', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emitsThrough(startsWith('[{"event":"app.started"')));
        await exitWebdev(webdev);
      });

      test('.debugPort', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(webdev.stdout,
            emitsThrough(startsWith('[{"event":"app.debugPort"')));
        await exitWebdev(webdev);
      });
    });
  }, tags: ['webdriver']);
}
