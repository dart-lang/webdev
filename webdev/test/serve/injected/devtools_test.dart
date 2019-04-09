// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
@Tags(['webdriver'])
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service_lib/vm_service_lib.dart';
import 'package:vm_service_lib/vm_service_lib_io.dart';
import 'package:webdriver/io.dart';

import 'injected_fixture.dart';

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

  group('Injected client', () {
    setUp(() async {
      fixture = await InjectedFixture.create();
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
      fixture = null;
    });

    test('can launch devtools', () async {
      var windows = await fixture.webdriver.windows.toList();

      await fixture.webdriver.driver.switchTo.window(windows.last);

      expect(await fixture.webdriver.title, 'Dart DevTools');
      await fixture.webdev.kill();
    });

    test('can not launch devtools for the same app in multiple tabs', () async {
      var appUrl = await fixture.webdriver.currentUrl;
      // Open a new tab, select it, and navigate to the app
      await fixture.webdriver.driver
          .execute("window.open('$appUrl', '_blank');", []);
      await Future.delayed(const Duration(seconds: 1));
      var windows = await fixture.webdriver.windows.toList();
      var oldAppWindow = windows[0];
      var newAppWindow = windows[1];
      var devToolsWindow = windows[2];
      await newAppWindow.setAsActive();

      // Try to open devtools and check for the alert.
      await fixture.webdriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
      await Future.delayed(const Duration(seconds: 1));
      var alert = fixture.webdriver.driver.switchTo.alert;
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
      await fixture.webdriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
      await Future.delayed(const Duration(seconds: 1));
      windows = await fixture.webdriver.windows.toList();
      devToolsWindow = windows.firstWhere((window) => window != newAppWindow);
      await devToolsWindow.setAsActive();
      expect(await fixture.webdriver.title, 'Dart DevTools');

      await fixture.webdev.kill();
    });

    test('can hot restart via the service extension', () async {
      var client = await vmServiceConnectUri(debugUri);
      await fixture.changeInput();

      expect(await client.callServiceExtension('hotRestart'),
          const TypeMatcher<Success>());
      await Future.delayed(const Duration(seconds: 2));

      var source = await fixture.webdriver.pageSource;
      // Main is re-invoked which shouldn't clear the state.
      expect(source, contains('Hello World!'));
      expect(source, contains('Gary is awesome!'));
      await fixture.webdev.kill();
    });

    test('destroys and recreates the isolate during a hot restart', () async {
      var client = await vmServiceConnectUri(debugUri);
      await client.streamListen('Isolate');
      await fixture.changeInput();

      var eventsDone = expectLater(
          client.onIsolateEvent,
          emitsThrough(emitsInOrder([
            predicate((Event event) => event.kind == EventKind.kIsolateExit),
            predicate((Event event) => event.kind == EventKind.kIsolateStart),
            predicate(
                (Event event) => event.kind == EventKind.kIsolateRunnable),
          ])));

      expect(await client.callServiceExtension('hotRestart'),
          const TypeMatcher<Success>());

      await eventsDone;
      await fixture.webdev.kill();
    });

    test('destroys and recreates the isolate during a page refresh', () async {
      var client = await vmServiceConnectUri(debugUri);
      await client.streamListen('Isolate');
      await fixture.changeInput();

      var eventsDone = expectLater(
          client.onIsolateEvent,
          emitsThrough(emitsInOrder([
            predicate((Event event) => event.kind == EventKind.kIsolateExit),
            predicate((Event event) => event.kind == EventKind.kIsolateStart),
            predicate(
                (Event event) => event.kind == EventKind.kIsolateRunnable),
          ])));

      await fixture.webdriver.driver.refresh();

      await eventsDone;
      await fixture.webdev.kill();
    });
  });

  test('gives a good error if --debug was not passed', () async {
    var fixture = await InjectedFixture.create();
    addTearDown(() => fixture.tearDown());
    await fixture.buildAndLoad([]);

    // Try to open devtools and check for the alert.
    await fixture.webdriver.driver.keyboard.sendChord([Keyboard.alt, 'd']);
    await Future.delayed(const Duration(seconds: 1));
    var alert = fixture.webdriver.driver.switchTo.alert;
    expect(alert, isNotNull);
    expect(await alert.text, contains('--debug'));
    await alert.accept();

    await fixture.webdev.kill();
  });
}
