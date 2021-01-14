// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/events.dart';
import 'package:test/test.dart';
import 'package:webdriver/async_core.dart';

import 'fixtures/context.dart';

void main() {
  final context = TestContext();
  setUpAll(() async {
    await context.setUp(
      serveDevTools: true,
    );
  });

  test('emits DEVTOOLS_LAUNCH event', () async {
    // The events stream is a broadcast stream so start listening before the
    // action.
    expect(context.testServer.dwds.events,
        emits(predicate((DwdsEvent event) => event.type == 'DEVTOOLS_LAUNCH')));
    await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
  });

  test('events can be listened to multiple times', () async {
    context.testServer.dwds.events.listen((_) {});
    context.testServer.dwds.events.listen((_) {});
  });
}
