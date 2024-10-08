// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:test/test.dart';

import '../test_utils.dart';
import 'utils.dart';

void main() {
  late String exampleDirectory;

  final testRunner = TestRunner();
  setUpAll(() async {
    await testRunner.setUpAll();
    exampleDirectory = await testRunner.prepareWorkspace();
  });

  tearDownAll(testRunner.tearDownAll);

  group('Daemon', () {
    group('Events', () {
      test('.connected', () async {
        final webdev = await testRunner
            .runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emits(startsWith('[{"event":"daemon.connected"')));
        await exitWebdev(webdev);
      });
    });

    group('Methods', () {
      test('.version', () async {
        final webdev = await testRunner
            .runWebDev(['daemon'], workingDirectory: exampleDirectory);
        webdev.stdin.add(utf8.encode('[{"method":"daemon.version","id":0}]\n'));
        await expectLater(
            webdev.stdout, emitsThrough(equals('[{"id":0,"result":"0.4.2"}]')));
        await exitWebdev(webdev);
      });

      test('.shutdown', () async {
        final webdev = await testRunner
            .runWebDev(['daemon'], workingDirectory: exampleDirectory);
        webdev.stdin
            .add(utf8.encode('[{"method":"daemon.shutdown","id":0}]\n'));
        await expectLater(webdev.stdout, emitsThrough(equals('[{"id":0}]')));
        expect(await webdev.exitCode, equals(0));
      });
    });
  });
}
