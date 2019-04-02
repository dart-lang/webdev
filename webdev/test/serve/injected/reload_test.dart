// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
import 'dart:io';

import 'package:test/test.dart';

import 'injected_fixture.dart';

void main() {
  InjectedFixture fixture;
  Process chromeDriver;

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
    });

    tearDown(() async {
      await fixture?.tearDown();
      fixture = null;
    });

    test('can hot restart changes ', () async {
      await fixture.buildAndLoad(['--auto=restart']);
      await fixture.changeInput();

      var source = await fixture.webdriver.pageSource;

      // Main is re-invoked which shouldn't clear the state.
      expect(source.contains('Hello World!'), isTrue);
      expect(source.contains('Gary is awesome!'), isTrue);
      // The ext.flutter.disassemble callback is invoked and waited for.
      expect(source,
          contains('start disassemble end disassemble Gary is awesome'));

      await fixture.webdev.kill();
    }, tags: ['requires-edge-sdk']);

    test('can live reload changes ', () async {
      await fixture.buildAndLoad(['--auto=refresh']);
      await fixture.changeInput();

      var source = await fixture.webdriver.pageSource;

      // A full reload should clear the state.
      expect(source.contains('Hello World!'), isFalse);
      expect(source.contains('Gary is awesome!'), isTrue);

      await fixture.webdev.kill();
    });
  }, tags: ['webdriver']);
}
