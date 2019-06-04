// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/serve/utils.dart';
import 'package:webdev/src/util.dart';
import 'package:webdriver/io.dart';

import '../../test_utils.dart';

class InjectedFixture {
  final File _entryFile;
  final String _entryContents;
  final String _exampleDirectory;
  WebDriver webdriver;
  TestProcess webdev;

  InjectedFixture._(
      this._entryFile, this._entryContents, this._exampleDirectory);

  Future<void> buildAndLoad(List<String> arg) async {
    var success = false;
    int debugPort;
    for (var attempt = 1; attempt <= 10; attempt++) {
      try {
        debugPort = await findUnusedPort();
        var capabilities = Capabilities.chrome
          ..addAll({
            Capabilities.chromeOptions: {
              'args': ['remote-debugging-port=$debugPort', '--headless']
            }
          });
        webdriver = await createDriver(
            spec: WebDriverSpec.JsonWire, desired: capabilities);
        success = true;
        break;
      } on SocketException {
        // AppVeyor can be flaky to start webdriver.
      }
    }
    if (!success) throw Exception('Unable to start webdriver.');

    var openPort = await findUnusedPort();
    var args = ['serve', 'web:$openPort', '--chrome-debug-port=$debugPort']
      ..addAll(arg);

    // This keeps the test open so kill it at the end :/
    webdev = await runWebDev(args, workingDirectory: _exampleDirectory);

    var hostUrl = 'http://localhost:$openPort';

    // Wait for the initial build to finish.
    await expectLater(webdev.stdout, emitsThrough(contains('Succeeded')));

    await webdriver.get(hostUrl);

    // Wait for the page to fully load.
    await Future.delayed(Platform.isWindows
        // AppVeyor is a little slower than Travis.
        ? const Duration(seconds: 5)
        : const Duration(seconds: 2));

    var source = await webdriver.pageSource;

    expect(source.contains('Hello World!'), isTrue);
  }

  Future<void> changeInput() async {
    _entryFile.writeAsStringSync(
        _entryContents.replaceAll('Hello World!', 'Gary is awesome!'));

    // Wait for the build.
    await expectLater(webdev.stdout, emitsThrough(contains('Succeeded')));

    // Allow change to propagate to the browser.
    await Future.delayed(const Duration(seconds: 2));
  }

  Future<void> tearDown() async {
    if (_entryContents != null) {
      _entryFile?.writeAsStringSync(_entryContents);
    }
    await webdriver?.quit();
    webdriver = null;
    await webdev?.kill();
    webdev = null;
  }

  static Future<InjectedFixture> create() async {
    var exampleDirectory =
        p.absolute(p.join(p.current, 'test', 'serve', 'injected', 'fixtures'));
    var entryFile = File(p.absolute(p.join(p.current, 'test', 'serve',
        'injected', 'fixtures', 'web', 'main.dart')));

    var entryContents = entryFile.readAsStringSync();

    var process = await TestProcess.start(pubPath, ['upgrade'],
        workingDirectory: exampleDirectory, environment: getPubEnvironment());

    await process.shouldExit(0);

    await d.file('.packages', isNotEmpty).validate(exampleDirectory);
    await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);

    return InjectedFixture._(entryFile, entryContents, exampleDirectory);
  }
}
