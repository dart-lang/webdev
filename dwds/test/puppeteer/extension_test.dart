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
import 'dart:convert';

import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/serializers.dart';
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';
import 'test_utils.dart';

final context = TestContext();

// Note: The following delay is required to reduce flakiness. It makes
// sure the service worker execution context is ready.
const executionContextDelay = 1;

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
          await context.setUp(
            launchChrome: false,
            useSse: useSse,
            enableDebugExtension: true,
          );
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

        test('the debug info for a Dart app is saved in the extension storage',
            () async {
          final appUrl = context.appUrl;
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          final worker = (await serviceWorkerTarget.worker)!;
          await Future.delayed(Duration(seconds: executionContextDelay));
          // Verify that we have debug info for the Dart app:
          final tabIdForAppJs = _tabIdForTabJs(appUrl);
          final appTabId = (await worker.evaluate(tabIdForAppJs)) as int;
          final debugInfoKey = '$appTabId-debugInfo';
          final storageObj =
              await worker.evaluate(_fetchStorageObjJs(debugInfoKey));
          final json = storageObj[debugInfoKey];
          final debugInfo =
              serializers.deserialize(jsonDecode(json)) as DebugInfo;
          expect(debugInfo.appId, isNotNull);
          expect(debugInfo.appEntrypointPath, isNotNull);
          expect(debugInfo.appInstanceId, isNotNull);
          expect(debugInfo.appOrigin, isNotNull);
          expect(debugInfo.appUrl, isNotNull);
          await appTab.close();
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
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          final worker = (await serviceWorkerTarget.worker)!;
          await Future.delayed(Duration(seconds: executionContextDelay));
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
          await appTab.close();
        });
      });
    }
  });
}

String _tabIdForTabJs(String tabUrl) {
  return '''
    async () => {
      const matchingTabs = await chrome.tabs.query({ url: "$tabUrl" });
      const tab = matchingTabs[0];
      return tab.id;
    }
''';
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

String _fetchStorageObjJs(String storageKey) {
  return '''
    async () => {
      const storageKey = "$storageKey";
      return new Promise((resolve, reject) => {
        chrome.storage.local.get(storageKey, (storageObj) => {
          if (storageObj != null) {
            resolve(storageObj);
          } else {
            resolve(null);
          }
        });
      });
    }
''';
}
