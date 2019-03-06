// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
import 'package:test/test.dart';

import 'injected_fixture.dart';

void main() {
  InjectedFixture fixture;

  group('Injected client', () {
    setUp(() async {
      fixture = await InjectedFixture.create();
    });

    tearDown(() async {
      await fixture?.tearDown();
      fixture = null;
    });

    test('can hot restart changes ', () async {
      await fixture.buildAndLoad(['--hot-restart']);
      await fixture.changeInput();

      var source = await fixture.webdriver.pageSource;

      // Main is re-invoked which shouldn't clear the state.
      expect(source.contains('Hello World!'), isTrue);
      expect(source.contains('Gary is awesome!'), isTrue);

      await fixture.webdev.kill();
    });

    test('can live reload changes ', () async {
      await fixture.buildAndLoad(['--live-reload']);
      await fixture.changeInput();

      var source = await fixture.webdriver.pageSource;

      // A full reload should clear the state.
      expect(source.contains('Hello World!'), isFalse);
      expect(source.contains('Gary is awesome!'), isTrue);

      await fixture.webdev.kill();
    });
  }, tags: ['webdriver']);
}
