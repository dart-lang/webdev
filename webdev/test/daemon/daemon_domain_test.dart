// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';

import '../test_utils.dart';

void main() {
  String exampleDirectory;

  setUpAll(() async {
    exampleDirectory = p.absolute(p.join(p.current, '..', 'example'));

    var process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: exampleDirectory, environment: getPubEnvironment());

    await process.shouldExit(0);

    await d.file('.packages', isNotEmpty).validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);
  });

  group('Daemon', () {
    group('Events', () {
      test('.connected', () async {
        var webdev =
            await runWebDev(['daemon'], workingDirectory: exampleDirectory);
        await expectLater(
            webdev.stdout, emits(startsWith('[{"event":"daemon.connected"')));
        await webdev.kill();
      });
    });

    test('.version', () async {
      var webdev =
          await runWebDev(['daemon'], workingDirectory: exampleDirectory);
      webdev.stdin.add(utf8.encode('[{"method":"daemon.version","id":0}]\n'));
      await expectLater(
          webdev.stdout, emitsThrough(equals('[{"id":0,"result":"0.4.2"}]')));
      await webdev.kill();
    });

    test('.shutdown', () async {
      var webdev =
          await runWebDev(['daemon'], workingDirectory: exampleDirectory);
      webdev.stdin.add(utf8.encode('[{"method":"daemon.shutdown","id":0}]\n'));
      await expectLater(webdev.stdout, emitsThrough(equals('[{"id":0}]')));
      expect(await webdev.exitCode, equals(0));
    });
  });
}
