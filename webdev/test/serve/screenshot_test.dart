// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 1))
@Tags(['webdriver'])
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart';
import 'package:webdriver/io.dart';

import 'injected/injected_fixture.dart';

void main() {
  InjectedFixture fixture;
  Process chromeDriver;
  String debugUri;

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

  setUp(() async {
    fixture = await InjectedFixture.create(headless: false);
    await fixture.buildAndLoad(['--debug']);
    await fixture.webdriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
    var debugServiceLine = '';
    while (!debugServiceLine.contains('Debug service listening')) {
      debugServiceLine = await fixture.webdev.stdout.next;
    }
    debugUri =
        debugServiceLine.substring(debugServiceLine.indexOf('ws://')).trim();

    // Let DevTools open.
    await Future.delayed(const Duration(seconds: 2));
  });

  tearDown(() async {
    await fixture.tearDown();
  });

  test('can take screenshots', () async {
    var windows = await fixture.webdriver.windows.toList();
    await fixture.webdriver.driver.switchTo.window(windows.first);
    var client = await vmServiceConnectUri(debugUri);
    var response = await client.callServiceExtension('ext.webdev.screenshot');
    expect(response.json['data'], isNotNull);
    await fixture.webdev.kill();
  });
}
