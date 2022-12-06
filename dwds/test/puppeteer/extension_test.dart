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
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../../debug_extension_mv3/web/data_serializers.dart';
import '../../debug_extension_mv3/web/data_types.dart';
import '../fixtures/context.dart';
import 'test_utils.dart';

final context = TestContext();

void main() async {
  late Worker worker;
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
            serveDevTools: true,
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

          final serviceWorkerTarget = await browser
              .waitForTarget((target) => target.type == 'service_worker');
          worker = (await serviceWorkerTarget.worker)!;
        });

        tearDown(() async {
          await workerEvalDelay();
          await worker.evaluate(_clearStorageJs());
        });

        tearDownAll(() async {
          await browser.close();
        });

        test('the debug info for a Dart app is saved in session storage',
            () async {
          final appUrl = context.appUrl;
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Verify that we have debug info for the Dart app:
          await workerEvalDelay();
          final appTabId = await _getTabId(appUrl, worker: worker);
          final debugInfoKey = '$appTabId-debugInfo';
          final debugInfo = await _fetchStorageObj<DebugInfo>(
            debugInfoKey,
            storageArea: 'session',
            worker: worker,
          );
          expect(debugInfo.appId, isNotNull);
          expect(debugInfo.appEntrypointPath, isNotNull);
          expect(debugInfo.appInstanceId, isNotNull);
          expect(debugInfo.appOrigin, isNotNull);
          expect(debugInfo.appUrl, isNotNull);
          expect(debugInfo.isInternalBuild, isNotNull);
          expect(debugInfo.isFlutterApp, isNotNull);
          await appTab.close();
        });

        test('whether to open in a new tab or window is saved in local storage',
            () async {
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
          // Check that is has been saved in local storage:
          final devToolsOpener = await _fetchStorageObj<DevToolsOpener>(
            'devToolsOpener',
            storageArea: 'local',
            worker: worker,
          );
          expect(devToolsOpener.newWindow, isTrue);
        });

        test(
            'can configure opening DevTools in a tab/window with extension settings',
            () async {
          final appUrl = context.appUrl;
          final devToolsUrlFragment =
              useSse ? 'debugger?uri=sse' : 'debugger?uri=ws';
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          await workerEvalDelay();
          await clickOnExtensionIcon(worker);
          // Verify the extension opened the Dart docs in the same window:
          var devToolsTabTarget = await browser.waitForTarget(
              (target) => target.url.contains(devToolsUrlFragment));
          var devToolsTab = await devToolsTabTarget.page;
          var devToolsWindowId = await _getWindowId(
            devToolsTab.url!,
            worker: worker,
          );
          var appWindowId = await _getWindowId(appUrl, worker: worker);
          expect(devToolsWindowId == appWindowId, isTrue);
          // Close the DevTools tab:
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
          await clickOnExtensionIcon(worker);
          // Verify the extension opened DevTools in a different window:
          devToolsTabTarget = await browser.waitForTarget(
              (target) => target.url.contains(devToolsUrlFragment));
          devToolsTab = await devToolsTabTarget.page;
          await devToolsTab.bringToFront();
          devToolsWindowId = await _getWindowId(
            devToolsTab.url!,
            worker: worker,
          );
          appWindowId = await _getWindowId(appUrl, worker: worker);
          expect(devToolsWindowId == appWindowId, isFalse);
          // Close the DevTools tab:
          devToolsTab = await devToolsTabTarget.page;
          await devToolsTab.close();
          await appTab.close();
        });

        test(
            'Navigating away from the Dart app while debugging closes DevTools',
            () async {
          final appUrl = context.appUrl;
          final devToolsUrlFragment =
              useSse ? 'debugger?uri=sse' : 'debugger?uri=ws';
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          await workerEvalDelay();
          await clickOnExtensionIcon(worker);
          // Verify that the Dart DevTools tab is open:
          final devToolsTabTarget = await browser.waitForTarget(
              (target) => target.url.contains(devToolsUrlFragment));
          expect(devToolsTabTarget.type, equals('page'));
          // Navigate away from the Dart app:
          await appTab.goto('https://dart.dev/', wait: Until.domContentLoaded);
          await appTab.bringToFront();
          // Verify that the Dart DevTools tab closes:
          await devToolsTabTarget.onClose;
          await appTab.close();
        });

        test('Closing the Dart app while debugging closes DevTools', () async {
          final appUrl = context.appUrl;
          final devToolsUrlFragment =
              useSse ? 'debugger?uri=sse' : 'debugger?uri=ws';
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          await workerEvalDelay();
          await clickOnExtensionIcon(worker);
          // Verify that the Dart DevTools tab is open:
          final devToolsTabTarget = await browser.waitForTarget(
              (target) => target.url.contains(devToolsUrlFragment));
          expect(devToolsTabTarget.type, equals('page'));
          // Close the Dart app:
          await appTab.close();
          // Verify that the Dart DevTools tab closes:
          await devToolsTabTarget.onClose;
        });
      });
    }
  });
}

Future<int> _getTabId(
  String url, {
  required Worker worker,
}) async {
  final jsExpression = _tabIdForTabJs(url);
  return (await worker.evaluate(jsExpression)) as int;
}

Future<int?> _getWindowId(
  String url, {
  required Worker worker,
}) async {
  final jsExpression = _windowIdForTabJs(url);
  return (await worker.evaluate(jsExpression)) as int?;
}

Future<T> _fetchStorageObj<T>(
  String storageKey, {
  required String storageArea,
  required Worker worker,
}) async {
  final storageObj = await worker.evaluate(_fetchStorageObjJs(
    storageKey,
    storageArea: storageArea,
  ));
  final json = storageObj[storageKey];
  return serializers.deserialize(jsonDecode(json)) as T;
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

String _fetchStorageObjJs(
  String storageKey, {
  required String storageArea,
}) {
  return '''
    async () => {
      const storageKey = "$storageKey";
      return new Promise((resolve, reject) => {
        chrome.storage.$storageArea.get(storageKey, (storageObj) => {
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

String _clearStorageJs() {
  return '''
    async () => {
      await chrome.storage.local.clear();
      await chrome.storage.session.clear();
      return true;
    }
''';
}
