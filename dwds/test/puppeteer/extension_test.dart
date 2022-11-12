// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@OnPlatform({
  // TODO(elliette): Enable on Windows.
  'windows': Skip('https://github.com/dart-lang/webdev/issues/1724'),
  // TODO(elliette): Enable on Linux.
  'linux': Skip('https://github.com/dart-lang/webdev/issues/1787'),
})
@Timeout(Duration(seconds: 60))
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

  group('MV3 Debug Extension', () {
    setUpAll(() async {
      extensionPath = await buildDebugExtension();
    });

    for (var useSse in [true, false]) {
      group(useSse ? 'with SSE' : 'with WebSockets', () {
        setUpAll(() async {
          // TODO(elliette): Only start a TestServer, that way we can get rid of
          // the launchChrome parameter: https://github.com/dart-lang/webdev/issues/1779
          await context.setUp(launchChrome: false, useSse: useSse);
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
            'can configure opening DevTools in a tab/window with extension settings',
            () async {
          final appUrl = context.appUrl;
          // TODO(elliette): Replace with the DevTools url.
          final devToolsUrl = 'https://dart.dev/';
          final windowIdForAppJs = _windowIdForTabJs(appUrl);
          final windowIdForDevToolsJs = _windowIdForTabJs(devToolsUrl);
          // Navigate to the Dart app:
          await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          final worker = (await serviceWorkerTarget.worker)!;
          // Note: The following delay is required to reduce flakiness (it makes
          // sure the execution context is ready):
          await Future.delayed(Duration(seconds: 1));
          await worker.evaluate(clickIconJs);
          // Verify the extension opened the Dart docs in the same window:
          var devToolsTabTarget = await browser
              .waitForTarget((target) => target.url.contains(devToolsUrl));
          var devToolsWindowId =
              (await worker.evaluate(windowIdForDevToolsJs)) as int?;
          var appWindowId = (await worker.evaluate(windowIdForAppJs)) as int?;
          expect(devToolsWindowId == appWindowId, isTrue);
          // Close the DevTools tab:
          var devToolsTab = await devToolsTabTarget.page;
          await devToolsTab.close();
          // Navigate to the extension settings page:
          final extensionOrigin = getExtensionOrigin(browser);
          final settingsTab = await navigateToPage(
            browser,
            url: '$extensionOrigin/settings.html',
            isNew: true,
          );
          // Set the settings to open DevTools in a new window:
          await settingsTab.tap('#windowOpt');
          await settingsTab.tap('#saveButton');
          // Wait for the saved message to verify settings have been saved:
          await settingsTab.waitForSelector('#savedMsg');
          // Close the settings tab:
          await settingsTab.close();
          // Navigate to the Dart app:
          await navigateToPage(browser, url: appUrl);
          // Click on the Dart Debug Extension icon:
          await worker.evaluate(clickIconJs);
          // Verify the extension opened DevTools in a different window:
          devToolsTabTarget = await browser
              .waitForTarget((target) => target.url.contains(devToolsUrl));
          devToolsWindowId =
              (await worker.evaluate(windowIdForDevToolsJs)) as int?;
          appWindowId = (await worker.evaluate(windowIdForAppJs)) as int?;
          expect(devToolsWindowId == appWindowId, isFalse);
          // Close the DevTools tab:
          devToolsTab = await devToolsTabTarget.page;
          await devToolsTab.close();
        });
      });
    }
  });
}

String _windowIdForTabJs(String tabUrl) {
  return '''
    async () => {
      const matchingTabs = await chrome.tabs.query({ url: "$tabUrl" });
      const tab = matchingTabs[0];
      return tab.windowId;
    }
''';
}
