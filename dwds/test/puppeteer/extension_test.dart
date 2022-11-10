// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO(elliette): Enable on Windows, see https://github.com/dart-lang/webdev/issues/1724.
@OnPlatform({
  'windows': Skip('https://github.com/dart-lang/webdev/issues/711'),
})
import 'dart:async';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/context.dart';

late Target serviceWorkerTarget;
late Browser browser;

final context = TestContext();

void main() async {
  for (var useSse in [true]) {
    group(useSse ? 'SSE' : 'WebSockets', () {
      setUpAll(() async {
        // TODO(elliette): Only start a TestServer, that way we can get rid of
        // the launchChrome parameter: https://github.com/dart-lang/webdev/issues/1779
        await context.setUp(launchChrome: false, useSse: useSse);
        final extensionPath = await _buildDebugExtension();
        browser = await puppeteer.launch(
          headless: false,
          args: [
            '--load-extension=$extensionPath',
            '--disable-extensions-except=$extensionPath',
            '--disable-features=DialMediaRouteProvider',
          ],
        );

        serviceWorkerTarget = await browser
            .waitForTarget((target) => target.type == 'service_worker');
        print('done with setup');
      });

      tearDownAll(() async {
        await browser.close();
      });

      test('Can use the MV3 Dart Debug Extension', () async {
        // Navigate to the Dart app:
        await _navigateToPage(browser, url: context.appUrl, isNew: true);
        final worker = (await serviceWorkerTarget.worker)!;
        final appTabWindowId = (await worker.evaluate(activeTabWindowIdJs)) as int?;
        /* 
        // Click on the Dart Debug Extension icon:
        await worker.evaluate(clickIconJs);
        // Verify that the extension opened the Dart docs in the same window as the Dart app:
        final openedTabTarget = await browser.waitForTarget(
            (target) => target.url.contains('https://dart.dev/'));
        await _navigateToPage(browser, url: 'https://dart.dev/');
        final activeTabUrl = (await worker.evaluate(activeTabUrlJs)) as String?;
        expect(activeTabUrl, equals('https://dart.dev/'));
        var activeTabWindowId = (await worker.evaluate(activeTabWindowIdJs)) as int?;
        expect(activeTabWindowId, equals(appTabWindowId));
        // Close the Dart docs tab:
        final openedTab = await openedTabTarget.page;
        await openedTab.close();
        */
        // Navigate to the extension settings page:
        final extensionOrigin = getExtensionOrigin(browser);
        final settingsTab = await _navigateToPage(browser, url: '$extensionOrigin/settings.html', isNew: true);
        // Set the settings to open the Dart Docs in a new window:
        await settingsTab.tap('#windowOpt');
        await Future.delayed(Duration(seconds: 3));
        await settingsTab.tap('#saveButton');
        await Future.delayed(Duration(seconds: 3));
        // Close the settings tab:
        await settingsTab.close();
        // Navigate to the Dart app:
        await _navigateToPage(browser, url: context.appUrl);
        // Click on the Dart Debug Extension icon:
        await worker.evaluate(clickIconJs);
        // Verify that the extension opened the Dart docs in a different window as the Dart app:
        final openedWindowTarget = await browser.waitForTarget(
            (target) => target.url.contains('https://dart.dev/'));
        await _navigateToPage(browser, url: 'https://dart.dev/');
        // activeTabUrl = (await worker.evaluate(activeTabUrlJs)) as String?;
        // expect(activeTabUrl, equals('https://dart.dev/'));
        final activeTabWindowId = (await worker.evaluate(activeTabWindowIdJs)) as int?;
        await Future.delayed(Duration(seconds: 3));
        print('activeTAbWindowId $activeTabWindowId');
        print('appTabWindowId $appTabWindowId');
        expect(activeTabWindowId == appTabWindowId, isFalse);

        final openedWindow = await openedWindowTarget.page;
        await openedWindow.close();
      });
    });
  }
}

Iterable<String> getUrlsInBrowser(Browser browser) {
  return browser.targets.map((target) => target.url);
}

Future<Page> _getPageForUrl(Browser browser, {required String url}) {
  final pageTarget = browser.targets.firstWhere((target) => target.url == url);
  return pageTarget.page;
}

String getExtensionOrigin(Browser browser) {
  final chromeExtension = 'chrome-extension:';
  final extensionUrl = getUrlsInBrowser(browser)
      .firstWhere((url) => url.contains(chromeExtension));
  final urlSegments = p.split(extensionUrl);
  final extensionId = urlSegments[urlSegments.indexOf(chromeExtension) + 1];
  return '$chromeExtension//$extensionId';
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

Future<String> _buildDebugExtension() async {
  final currentDir = Directory.current.path;
  if (!currentDir.endsWith('dwds')) {
    throw StateError(
        'Expected to be in /dwds directory, instead path was $currentDir.');
  }
  final extensionDir = '$currentDir/debug_extension_mv3';
  // TODO(elliette): This doesn't work on Windows, see https://github.com/dart-lang/webdev/issues/1724.
  await Process.run(
    'tool/build_extension.sh',
    [],
    workingDirectory: extensionDir,
  );
  return '$extensionDir/compiled';
}

final clickIconJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    chrome.action.onClicked.dispatch(tab);
  }
''';

final activeTabUrlJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    return tab.url;
  }
''';

final activeTabWindowIdJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    return tab.windowId;
  }
''';
