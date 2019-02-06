// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(const Duration(minutes: 5))
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';
import 'package:webdriver/io.dart';

import '../test_utils.dart';

void main() {
  File entryFile;
  String entryContents;
  String exampleDirectory;
  WebDriver webdriver;
  TestProcess webdev;

  setUpAll(() async {
    exampleDirectory =
        p.absolute(p.join(p.current, 'test', 'reload_client', 'fixtures'));
    entryFile = File(p.absolute(p.join(
        p.current, 'test', 'reload_client', 'fixtures', 'web', 'main.dart')));

    entryContents = entryFile.readAsStringSync();

    var process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: exampleDirectory, environment: getPubEnvironment());

    await process.shouldExit(0);

    await d.file('.packages', isNotEmpty).validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);
  });

  tearDown(() async {
    if (entryContents != null) {
      entryFile?.writeAsStringSync(entryContents);
    }
    await webdriver?.close();
    await webdev?.kill();
  });

  test('Can hot restart changes ', () async {
    var openPort = await getOpenPort();
    var args = ['serve', 'web:$openPort', '--hot-restart'];

    // This keeps the test open so kill it at the end :/
    webdev = await runWebDev(args, workingDirectory: exampleDirectory);

    var hostUrl = 'http://localhost:$openPort';

    // Wait for the initial build to finish.
    await expectLater(webdev.stdout, emitsThrough(contains('Succeeded')));

    webdriver = await createDriver();
    await webdriver.get(hostUrl);

    // Wait for the build
    await Future.delayed(const Duration(seconds: 2));

    var source = await webdriver.pageSource;

    expect(source.contains('Hello World!'), isTrue);

    entryFile.writeAsStringSync(
        entryContents.replaceAll('Hello World!', 'Gary is awesome!'));

    // Wait for the build
    await Future.delayed(const Duration(seconds: 5));

    source = await webdriver.pageSource;

    // Main is re-invoked which shouldn't clear the state.
    expect(source.contains('Hello World!'), isTrue);
    expect(source.contains('Gary is awesome!'), isTrue);

    await webdev.kill();
  });

  test('Can live reload changes ', () async {
    var openPort = await getOpenPort();
    var args = ['serve', 'web:$openPort', '--live-reload'];

    // This keeps the test open so kill it at the end :/
    webdev = await runWebDev(args, workingDirectory: exampleDirectory);

    var hostUrl = 'http://localhost:$openPort';

    // Wait for the initial build to finish.
    await expectLater(webdev.stdout, emitsThrough(contains('Succeeded')));

    webdriver = await createDriver();
    await webdriver.get(hostUrl);

    // Wait for the build
    await Future.delayed(const Duration(seconds: 2));

    var source = await webdriver.pageSource;

    expect(source.contains('Hello World!'), isTrue);

    entryFile.writeAsStringSync(
        entryContents.replaceAll('Hello World!', 'Gary is awesome!'));

    // Wait for the build
    await Future.delayed(const Duration(seconds: 5));

    source = await webdriver.pageSource;

    // A full reload should clear the state.
    expect(source.contains('Hello World!'), isFalse);
    expect(source.contains('Gary is awesome!'), isTrue);

    await webdev.kill();
  });
}
