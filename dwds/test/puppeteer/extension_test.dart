// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@OnPlatform({
  // TODO(elliette): Enable on Windows.
  'windows': Skip('https://github.com/dart-lang/webdev/issues/1724'),
  // TODO(elliette): Enable on Linux.
  'linux': Skip('https://github.com/dart-lang/webdev/issues/1787'),
})
@Timeout(Duration(minutes: 2))
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dwds/data/debug_info.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../../debug_extension_mv3/web/data_serializers.dart';
import '../../debug_extension_mv3/web/data_types.dart';
import '../fixtures/context.dart';
import 'test_utils.dart';

final context = TestContext();

enum Panel { debugger, inspector }

void main() async {
  group('MV3 Debug Extension', () {
    late String extensionPath;

    setUpAll(() async {
      extensionPath = await buildDebugExtension();
    });

    for (var useSse in [true, false]) {
      group(useSse ? 'connected with SSE:' : 'connected with WebSockets:', () {
        late Browser browser;
        late Worker worker;

        setUpAll(() async {
          browser = await setUpExtensionTest(
            context,
            extensionPath: extensionPath,
            serveDevTools: true,
            useSse: useSse,
          );
          worker = await getServiceWorker(browser);

          // Navigate to the Chrome extension page instead of the blank tab
          // opened by Chrome. This is helpful for local debugging.
          final blankTab = await navigateToPage(browser, url: 'about:blank');
          await blankTab.goto('chrome://extensions/');
        });

        tearDown(() async {
          await workerEvalDelay();
          await worker.evaluate(_clearStorageJs());
          await workerEvalDelay();
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
            url: '$extensionOrigin/static_assets/settings.html',
            isNew: true,
          );
          // Set the settings to open DevTools in a new window:
          await settingsTab.tap('#windowOpt');
          await settingsTab.tap('#saveButton');
          // Wait for the saved message to verify settings have been saved:
          await settingsTab.waitForSelector('.show');
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
          devToolsTab = await devToolsTabTarget.page;
          await devToolsTab.close();
          // Navigate to the extension settings page:
          final extensionOrigin = getExtensionOrigin(browser);
          final settingsTab = await navigateToPage(
            browser,
            url: '$extensionOrigin/static_assets/settings.html',
            isNew: true,
          );
          // Set the settings to open DevTools in a new window:
          await settingsTab.tap('#windowOpt');
          await settingsTab.tap('#saveButton');
          // Wait for the saved message to verify settings have been saved:
          await settingsTab.waitForSelector('.show');
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
            'navigating away from the Dart app while debugging closes DevTools',
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

        test('closing the Dart app while debugging closes DevTools', () async {
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

    group('connected to an externally-built', () {
      for (var isFlutterApp in [true, false]) {
        group(isFlutterApp ? 'Flutter app:' : 'Dart app:', () {
          late Browser browser;
          late Worker worker;

          setUpAll(() async {
            browser = await setUpExtensionTest(
              context,
              extensionPath: extensionPath,
              serveDevTools: true,
              isInternalBuild: false,
              isFlutterApp: isFlutterApp,
              openChromeDevTools: true,
            );

            worker = await getServiceWorker(browser);
          });

          tearDown(() async {
            await workerEvalDelay();
            await worker.evaluate(_clearStorageJs());
          });

          tearDownAll(() async {
            await browser.close();
          });
          test(
              'isFlutterApp=$isFlutterApp and isInternalBuild=false are saved in storage',
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
            expect(debugInfo.isInternalBuild, equals(false));
            expect(debugInfo.isFlutterApp, equals(isFlutterApp));
            await appTab.close();
          });

          test('no additional panels are added in Chrome DevTools', () async {
            final appUrl = context.appUrl;
            // This is the blank page automatically opened by Chrome:
            final blankTab = await navigateToPage(browser, url: 'about:blank');
            // Navigate to the Dart app:
            await blankTab.goto(appUrl, wait: Until.domContentLoaded);
            final appTab = blankTab;
            await appTab.bringToFront();
            final chromeDevToolsTarget = browser.targets.firstWhere(
                (target) => target.url.startsWith('devtools://devtools'));
            chromeDevToolsTarget.type = 'page';
            final chromeDevToolsPage = await chromeDevToolsTarget.page;
            _tabLeft(chromeDevToolsPage);
            await _takeScreenshot(chromeDevToolsPage,
                screenshotName: 'chromeDevTools_externalBuild');
            final inspectorPanelTarget = browser.targets
                .firstWhereOrNull((target) => target.url == 'inspector_panel');
            expect(inspectorPanelTarget, isNull);
            final debuggerPanelTarget = browser.targets
                .firstWhereOrNull((target) => target.url == 'debugger_panel');
            expect(debuggerPanelTarget, isNull);
          });
        });
      }
    });

    group('connected to an internally-built', () {
      for (var isFlutterApp in [true, false]) {
        group(isFlutterApp ? 'Flutter app:' : 'Dart app:', () {
          late Browser browser;
          late Worker worker;

          setUpAll(() async {
            browser = await setUpExtensionTest(
              context,
              extensionPath: extensionPath,
              serveDevTools: true,
              isInternalBuild: true,
              isFlutterApp: isFlutterApp,
              openChromeDevTools: true,
            );

            worker = await getServiceWorker(browser);
          });

          tearDown(() async {
            await workerEvalDelay();
            await worker.evaluate(_clearStorageJs());
            await workerEvalDelay();
          });

          tearDownAll(() async {
            await browser.close();
          });
          test(
              'isFlutterApp=$isFlutterApp and isInternalBuild=true are saved in storage',
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
            expect(debugInfo.isInternalBuild, equals(true));
            expect(debugInfo.isFlutterApp, equals(isFlutterApp));
            await appTab.close();
          });

          test('the correct extension panels are added to Chrome DevTools',
              () async {
            final appUrl = context.appUrl;
            // This is the blank page automatically opened by Chrome:
            final blankTab = await navigateToPage(browser, url: 'about:blank');
            // Navigate to the Dart app:
            await blankTab.goto(appUrl, wait: Until.domContentLoaded);
            final appTab = blankTab;
            await appTab.bringToFront();
            final chromeDevToolsTarget = browser.targets.firstWhere(
                (target) => target.url.startsWith('devtools://devtools'));
            chromeDevToolsTarget.type = 'page';
            final chromeDevToolsPage = await chromeDevToolsTarget.page;
            // There are no hooks for when a panel is added to Chrome DevTools,
            // therefore we rely on a slight delay:
            await Future.delayed(Duration(seconds: 1));
            if (isFlutterApp) {
              _tabLeft(chromeDevToolsPage);
              final inspectorPanelElement =
                  await _getPanelElement(browser, panel: Panel.inspector);
              expect(inspectorPanelElement, isNotNull);
              await _takeScreenshot(
                chromeDevToolsPage,
                screenshotName: 'inspectorPanelLandingPage_flutterApp',
              );
            }
            _tabLeft(chromeDevToolsPage);
            final debuggerPanelElement =
                await _getPanelElement(browser, panel: Panel.debugger);
            expect(debuggerPanelElement, isNotNull);
            await _takeScreenshot(
              chromeDevToolsPage,
              screenshotName:
                  'debuggerPanelLandingPage_${isFlutterApp ? 'flutterApp' : 'dartApp'}',
            );
          });
        });
      }
    });
  });
}

Future<ElementHandle?> _getPanelElement(
  Browser browser, {
  required Panel panel,
}) async {
  final panelName =
      panel == Panel.inspector ? 'inspector_panel' : 'debugger_panel';
  final panelTarget =
      await browser.waitForTarget((target) => target.url.contains(panelName));
  panelTarget.type = 'page';
  final panelPage = await panelTarget.page;
  final frames = panelPage.frames;
  final mainFrame = frames[0];
  final panelElement = await mainFrame.$OrNull('#panelBody');
  return panelElement;
}

void _tabLeft(Page chromeDevToolsPage) async {
  // TODO(elliette): Detect which enviroment we are OS we are running
  // in and update modifier key accordingly. Meta key for MacOs and
  // Ctrl key for Linux/Windows.
  final modifierKey = Key.meta;
  await chromeDevToolsPage.keyboard.down(modifierKey);
  await chromeDevToolsPage.keyboard.press(Key.bracketLeft);
  await chromeDevToolsPage.keyboard.up(modifierKey);
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

Future<void> _takeScreenshot(
  Page page, {
  required String screenshotName,
}) async {
  // Since the DevTools panels are not real "pages" but merely targets we have
  // coerced into having a "page" type, there doesn't seem to be a way to verify
  // that the DOM has been loaded. Therefore we use a slight delay before taking
  // a screenshot. See https://github.com/puppeteer/puppeteer/issues/9371.
  await Future.delayed(Duration(seconds: 1));
  final screenshot = await page.screenshot();
  final screenshotPath =
      p.join('test', 'puppeteer', 'test_images', '$screenshotName.png');
  await File(screenshotPath).writeAsBytes(screenshot);
}
