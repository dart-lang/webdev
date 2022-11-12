// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 10))
@Skip('https://github.com/dart-lang/webdev/issues/1788')
import 'dart:async';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';
import 'test_utils.dart';

final context = TestContext();

void main() async {
  late Target serviceWorkerTarget;
  late Browser browser;
  late String extensionPath;

  int connectionCount = 0;

  group('MV3 Debug Extension Lifeline Connection', () {
    setUpAll(() async {
      extensionPath = await buildDebugExtension();
      await context.setUp(launchChrome: false);
      browser = await puppeteer.launch(
        headless: false,
        timeout: Duration(seconds: 60),
        args: [
          '--load-extension=$extensionPath',
          '--disable-extensions-except=$extensionPath',
          '--disable-features=DialMediaRouteProvider',
        ],
      );

      serviceWorkerTarget = await browser
          .waitForTarget((target) => target.type == 'service_worker');
    });

    tearDownAll(() async {
      await browser.close();
    });

    test('connects to a lifeline port', () async {
      // Navigate to the Dart app:
      final appTab =
          await navigateToPage(browser, url: context.appUrl, isNew: true);
      // Click on the Dart Debug Extension icon:
      final worker = (await serviceWorkerTarget.worker)!;
      // Note: The following delay is required to reduce flakiness (it makes
      // sure the execution context is ready):
      await Future.delayed(Duration(seconds: 1));
      // Initiate listeners for the port connection event and the subsequent
      // reconnection logs:
      final portConnectionPromise = worker.evaluate<bool>(_portConnectionJs);
      appTab.onConsole.listen((ConsoleMessage message) {
        final messageText = message.text ?? '';
        if (messageText
            .contains('[Dart Debug Extension] Connecting to lifeline port')) {
          connectionCount++;
        }
      });
      // Click on the Dart Debug Extension icon to intiate a debug session:
      await worker.evaluate(clickIconJs);
      final connectedToPort = await portConnectionPromise;
      // Verify that we have connected to the port:
      expect(connectedToPort, isTrue);
      expect(connectionCount, equals(1));
      // Wait for a little over 5 minutes, and verify that we have reconnected
      // to the port again:
      await Future.delayed(Duration(minutes: 5) + Duration(seconds: 15));
      expect(connectionCount, equals(2));
    });
  });
}

final _portConnectionJs = '''
  async () => {
    return new Promise((resolve, reject) => {
      chrome.runtime.onConnect.addListener((port) => {
        if (port.name == 'keepAlive') {
          resolve(true);
        } else {
          reject(false);
        }
      });
    });
  }
''';
