// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
import 'dart:async';

import 'package:test/test.dart';
import 'package:webdriver/io.dart';

import 'injected_fixture.dart';

// To run locally first run:
//  chromedriver --port=4444 --url-base=wd/hub --verbose
void main() {
  InjectedFixture fixture;

  group('Injected client', () {
    setUp(() async {
      fixture = await InjectedFixture.create();
    });

    tearDown(() async {
      await fixture.tearDown();
      fixture = null;
    });

    test('can can launch devtools', () async {
      await fixture.buildAndLoad(['--debug']);

      await fixture.webdriver.driver.keyboard.sendKeys('${Keyboard.alt}d');

      // Let DevTools open.
      await Future.delayed(const Duration(seconds: 2));

      var windows = await fixture.webdriver.windows.toList();

      await fixture.webdriver.driver.switchTo.window(windows.last);

      expect(await fixture.webdriver.title, 'Dart DevTools');

      await fixture.webdev.kill();
    });
  }, tags: ['webdriver']);
}
