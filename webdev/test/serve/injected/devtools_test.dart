// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
@Tags(['requires-edge-sdk'])
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart';
import 'package:webdriver/io.dart';

import 'injected_fixture.dart';

void main() {
  InjectedFixture fixture;
  Process chromeDriver;
  int debugPort;

  setUpAll(() async {
    try {
      chromeDriver = await Process.start(
          'chromedriver', ['--port=4444', '--url-base=wd/hub']);
    } catch (e) {
      throw StateError(
          'Could not start ChromeDriver. Is it installed?\nError: $e');
    }
  });

  tearDownAll(() {
    chromeDriver.kill();
  });

  group('Injected client', () {
    setUp(() async {
      fixture = await InjectedFixture.create();
      await fixture.buildAndLoad(['--debug']);
      await fixture.webdriver.driver.keyboard.sendKeys('${Keyboard.alt}d');
      var debugServiceLine = '';
      while (!debugServiceLine.startsWith('Debug service listening')) {
        debugServiceLine = await fixture.webdev.stdout.next;
      }
      debugPort = int.parse(debugServiceLine.split(':').last.trim());

      // Let DevTools open.
      await Future.delayed(const Duration(seconds: 2));
    });

    tearDown(() async {
      await fixture.tearDown();
      fixture = null;
    });

    test('can launch devtools', () async {
      var windows = await fixture.webdriver.windows.toList();

      await fixture.webdriver.driver.switchTo.window(windows.last);

      expect(await fixture.webdriver.title, 'Dart DevTools');
    });

    test('can hot restart via the service extension', () async {
      await fixture.buildAndLoad(['--debug']);
      await fixture.changeInput();

      var client = await vmServiceConnect('localhost', debugPort);
      await client.callServiceExtension('hotRestart');
      await Future.delayed(const Duration(seconds: 2));

      var source = await fixture.webdriver.pageSource;
      // Main is re-invoked which shouldn't clear the state.
      expect(source.contains('Hello World!'), isTrue);
      expect(source.contains('Gary is awesome!'), isTrue);
    });
  }, tags: ['webdriver']);
}
