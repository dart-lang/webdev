// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
@Timeout(Duration(minutes: 10))
library lifeline_test;

import 'dart:async';

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

// import '../fixtures/context.dart';

// final context = TestContext();

void main() async {
  late Target serviceWorkerTarget;
  late Browser browser;

  group('MV3 Debug Extension Lifeline Connection', () {
    setUpAll(() async {
      // Don't hard code the following:
      final extensionPath = '/Users/elliottbrooks/dev/webdev/dwds/debug_extension_mv3/compiled';
      // await context.setUp(launchChrome: false);
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

    test(
        'connects to a lifeline port',
        () async {
      final appUrl = 'https://www.wikipedia.org/';
      // Navigate to the Dart app:
      await _navigateToPage(browser, url: appUrl, isNew: true);
      // Click on the Dart Debug Extension icon:
      final worker = (await serviceWorkerTarget.worker)!;
      // Note: The following delay is required to reduce flakiness (it makes
      // sure the execution context is ready):
      await Future.delayed(Duration(seconds: 1));
      final portConnectionPromise = worker.evaluate(_portConnectionJs);
      await worker.evaluate(_clickIconJs);
      final connectedToPort = await promiseToFuture<bool>(portConnectionPromise);
      expect(connectedToPort, isTrue);
    });
  });
}

Future<Page> _getPageForUrl(Browser browser, {required String url}) {
  final pageTarget = browser.targets.firstWhere((target) => target.url == url);
  return pageTarget.page;
}

Future<Page> _navigateToPage(
  Browser browser, {
  required String url,
  bool isNew = false,
}) async {
  final page = isNew
      ? await browser.newPage()
      : await _getPageForUrl(
          browser,
          url: url,
        );
  if (isNew) {
    await page.goto(url, wait: Until.domContentLoaded);
  }
  await page.bringToFront();
  return page;
}

final _clickIconJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    chrome.action.onClicked.dispatch(tab);
  }
''';

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
