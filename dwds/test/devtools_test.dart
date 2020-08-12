// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
@TestOn('vm')
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webdriver/io.dart';

import 'fixtures/context.dart';

final context = TestContext(
  path: 'append_body/index.html',
);

Future<void> _waitForPageReady(TestContext context) async {
  var attempt = 100;
  while (attempt-- > 0) {
    var content = await context.webDriver.pageSource;
    if (content.contains('Hello World!')) return;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Page never initialized');
}

void main() {
  group('Injected client', () {
    setUp(() async {
      await context.setUp(serveDevTools: true);
      await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
      // Wait for DevTools to actually open.
      await Future.delayed(const Duration(seconds: 2));
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('can launch devtools', () async {
      var windows = await context.webDriver.windows.toList();
      await context.webDriver.driver.switchTo.window(windows.last);
      // TODO(grouma): switch back to `fixture.webdriver.title` when
      // https://github.com/flutter/devtools/issues/2045 is fixed.
      expect(await context.webDriver.pageSource, contains('Flutter'));
    });

    test('can not launch devtools for the same app in multiple tabs', () async {
      var appUrl = await context.webDriver.currentUrl;
      // Open a new tab, select it, and navigate to the app
      await context.webDriver.driver
          .execute("window.open('$appUrl', '_blank');", []);
      await Future.delayed(const Duration(seconds: 2));
      var windows = await context.webDriver.windows.toList();
      var oldAppWindow = windows[0];
      var newAppWindow = windows[1];
      var devToolsWindow = windows[2];
      await newAppWindow.setAsActive();

      // Wait for the page to be ready before trying to open DevTools again.
      await _waitForPageReady(context);

      // Try to open devtools and check for the alert.
      await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
      await Future.delayed(const Duration(seconds: 2));
      var alert = context.webDriver.driver.switchTo.alert;
      expect(alert, isNotNull);
      expect(await alert.text,
          contains('This app is already being debugged in a different tab'));
      await alert.accept();

      // Now close the old app and try to re-open devtools.
      await oldAppWindow.setAsActive();
      await oldAppWindow.close();
      await devToolsWindow.setAsActive();
      await devToolsWindow.close();
      await newAppWindow.setAsActive();
      await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
      await Future.delayed(const Duration(seconds: 2));
      windows = await context.webDriver.windows.toList();
      devToolsWindow = windows.firstWhere((window) => window != newAppWindow);
      await devToolsWindow.setAsActive();
      // TODO(grouma): switch back to `fixture.webdriver.title` when
      // https://github.com/flutter/devtools/issues/2045 is fixed.
      expect(await context.webDriver.pageSource, contains('Flutter'));
    });

    test('destroys and recreates the isolate during a page refresh', () async {
      // This test is the same as one in reload_test, but runs here when there
      // is a connected client (DevTools) since it can behave differently.
      // https://github.com/dart-lang/webdev/pull/901#issuecomment-586438132
      var client = context.debugConnection.vmService;
      await client.streamListen('Isolate');
      await context.changeInput();

      var eventsDone = expectLater(
          client.onIsolateEvent,
          emitsThrough(emitsInOrder([
            _hasKind(EventKind.kIsolateExit),
            _hasKind(EventKind.kIsolateStart),
            _hasKind(EventKind.kIsolateRunnable),
          ])));

      await context.webDriver.driver.refresh();

      await eventsDone;
    });
  });

  group('Injected client without DevTools', () {
    setUp(() async {
      await context.setUp(serveDevTools: false);
    });

    tearDown(() async {
      await context.tearDown();
    });

    test('gives a good error if devtools is not served', () async {
      // Try to open devtools and check for the alert.
      await context.webDriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
      await Future.delayed(const Duration(seconds: 2));
      var alert = context.webDriver.driver.switchTo.alert;
      expect(alert, isNotNull);
      expect(await alert.text, contains('--debug'));
      await alert.accept();
    });
  });
}

TypeMatcher<Event> _hasKind(String kind) =>
    isA<Event>().having((e) => e.kind, 'kind', kind);
