// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))

import 'dart:convert';

import 'package:test/test.dart';

import '../test_utils.dart';
import 'utils.dart';

void main() {
  String exampleDirectory;

  setUpAll(() async {
    exampleDirectory = await prepareWorkspace();
  });

  group('Daemon', () {
    group('Events', () {
      test('.connected', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emits(startsWith('[{"event":"daemon.connected"')));
        await exitWebdev(webdev);
      });
    });

    group('Methods', () {
      test('.version', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        webdev.stdin.add(utf8.encode('[{"method":"daemon.version","id":0}]\n'));
        await expectLater(
            webdev.stdout, emitsThrough(equals('[{"id":0,"result":"0.4.2"}]')));
        await exitWebdev(webdev);
      });

      test('.shutdown', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        webdev.stdin
            .add(utf8.encode('[{"method":"daemon.shutdown","id":0}]\n'));
        await expectLater(webdev.stdout, emitsThrough(equals('[{"id":0}]')));
        expect(await webdev.exitCode, equals(0));
      });
    });
  });
}
