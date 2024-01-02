// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/src/servers/extension_backend.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart' hide Response;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:test_common/utilities.dart';

import '../../debug_extension_mv3/web/data_serializers.dart';
import '../fixtures/context.dart';
import '../fixtures/project.dart';
import '../fixtures/utilities.dart';
import 'test_utils.dart';

enum Panel { debugger, inspector }

late bool screenshotsEnabled;

void testAll({
  required bool isMV3,
  required bool screenshotsEnabled,
}) {
  screenshotsEnabled = screenshotsEnabled;

  final provider = TestSdkConfigurationProvider();
  final context = TestContext(TestProject.testWithSoundNullSafety, provider);
  tearDownAll(provider.dispose);

  group('${isMV3 ? 'MV3' : 'MV2'} Debug Extension', () {
    late String extensionPath;

    setUpAll(() async {
      extensionPath = await buildDebugExtension(isMV3: isMV3);
    });

    for (var useSse in [true, false]) {
      group(useSse ? 'connected with SSE:' : 'connected with WebSockets:', () {
        late Browser browser;
        Worker? worker;
        Page? backgroundPage;

        setUpAll(() async {
          browser = await setUpExtensionTest(
            context,
            extensionPath: extensionPath,
            serveDevTools: true,
            useSse: useSse,
            workspaceName: 'test-workspace',
          );

          if (isMV3) {
            worker = await getServiceWorker(browser);
          } else {
            backgroundPage = await getBackgroundPage(browser);
          }

          // Navigate to the Chrome extension page instead of the blank tab
          // opened by Chrome. This is helpful for local debugging.
          final blankTab = await navigateToPage(browser, url: 'about:blank');
          await blankTab.goto('chrome://extensions/');
        });

        tearDown(() async {
          await tearDownHelper(
            worker: worker,
            backgroundPage: backgroundPage,
          );
        });

        tearDownAll(() async {
          await browser.close();
          await context.tearDown();
        });

        test('the debug info for a Dart app is saved in session storage',
            () async {
          final appUrl = context.appUrl;
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Verify that we have debug info for the Dart app:
          await workerEvalDelay();
          final appTabId = await _getCurrentTabId(
            worker: worker,
            backgroundPage: backgroundPage,
          );
          final debugInfoKey = '$appTabId-debugInfo';
          final debugInfo = await _fetchStorageObj<DebugInfo>(
            debugInfoKey,
            storageArea: 'session',
            worker: worker,
            backgroundPage: backgroundPage,
          );
          expect(debugInfo.appId, isNotNull);
          expect(debugInfo.appEntrypointPath, isNotNull);
          expect(debugInfo.appInstanceId, isNotNull);
          expect(debugInfo.appOrigin, isNotNull);
          expect(debugInfo.appUrl, isNotNull);
          expect(debugInfo.isInternalBuild, isNotNull);
          expect(debugInfo.isFlutterApp, isNotNull);
          expect(debugInfo.workspaceName, isNotNull);
          await appTab.close();
        });

        test('the auth status is saved in session storage', () async {
          final appUrl = context.appUrl;
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Verify that we have debug info for the Dart app:
          await workerEvalDelay();
          final appTabId = await _getCurrentTabId(
            worker: worker,
            backgroundPage: backgroundPage,
          );
          final authKey = '$appTabId-isAuthenticated';
          final authenticated = await _fetchStorageObj<String>(
            authKey,
            storageArea: 'session',
            worker: worker,
            backgroundPage: backgroundPage,
          );
          expect(authenticated, isNotNull);
          expect(authenticated, equals('true'));
          await appTab.close();
        });

        test('DevTools is opened with the correct query parameters', () async {
          final appUrl = context.appUrl;
          final devToolsUrlFragment =
              useSse ? 'debugger?uri=sse' : 'debugger?uri=ws';
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          await workerEvalDelay();
          await clickOnExtensionIcon(
            browser: browser,
            worker: worker,
            backgroundPage: backgroundPage,
          );
          // Wait for DevTools to open:
          final devToolsTabTarget = await browser.waitForTarget(
            (target) => target.url.contains(devToolsUrlFragment),
          );
          final devToolsUrl = devToolsTabTarget.url;
          // Expect the correct query parameters to be on the DevTools url:
          final uri = Uri.parse(devToolsUrl);
          final queryParameters = uri.queryParameters;
          expect(queryParameters.keys, unorderedMatches(['uri', 'ide']));
          expect(queryParameters, containsPair('ide', 'DebugExtension'));
          expect(queryParameters, containsPair('uri', isNotEmpty));
          // Close the DevTools tab:
          final devToolsTab = await devToolsTabTarget.page;
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
          await clickOnExtensionIcon(
            browser: browser,
            worker: worker,
            backgroundPage: backgroundPage,
          );
          // Verify that the Dart DevTools tab is open:
          final devToolsTabTarget = await browser.waitForTarget(
            (target) => target.url.contains(devToolsUrlFragment),
          );
          expect(devToolsTabTarget.type, equals('page'));
          // Navigate away from the Dart app:
          await appTab.goto(
            'https://dart.dev/',
            wait: Until.domContentLoaded,
          );
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
          await clickOnExtensionIcon(
            browser: browser,
            worker: worker,
            backgroundPage: backgroundPage,
          );
          // Verify that the Dart DevTools tab is open:
          final devToolsTabTarget = await browser.waitForTarget(
            (target) => target.url.contains(devToolsUrlFragment),
          );
          expect(devToolsTabTarget.type, equals('page'));
          // Close the Dart app:
          await appTab.close();
          // Verify that the Dart DevTools tab closes:
          await devToolsTabTarget.onClose;
        });

        test('Clicking extension icon while debugging shows warning', () async {
          final appUrl = context.appUrl;
          final devToolsUrlFragment =
              useSse ? 'debugger?uri=sse' : 'debugger?uri=ws';
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          await workerEvalDelay();
          await clickOnExtensionIcon(
            browser: browser,
            worker: worker,
            backgroundPage: backgroundPage,
          );
          // Wait for Dart Devtools to open:
          final devToolsTabTarget = await browser.waitForTarget(
            (target) => target.url.contains(devToolsUrlFragment),
          );
          // There should be no warning notifications:
          var chromeNotifications = await evaluate(
            _getNotifications(),
            worker: worker,
            backgroundPage: backgroundPage,
          );
          expect(chromeNotifications, isEmpty);
          // Navigate back to Dart app:
          await navigateToPage(browser, url: appUrl, isNew: false);
          // Click on the Dart Debug Extension icon again:
          await workerEvalDelay();
          await clickOnExtensionIcon(
            browser: browser,
            worker: worker,
            backgroundPage: backgroundPage,
          );
          await workerEvalDelay();
          // There should now be a warning notification:
          chromeNotifications = await evaluate(
            _getNotifications(),
            worker: worker,
            backgroundPage: backgroundPage,
          );
          expect(chromeNotifications, isNotEmpty);
          // Close the Dart app and the associated Dart DevTools:
          await appTab.close();
          await devToolsTabTarget.onClose;
        });

        test('Clicking extension icon for a non Dart app shows warning',
            () async {
          // Navigate to a page that doesn't contain a Dart app:
          final tab = await navigateToPage(
            browser,
            url: 'https://dart.dev',
            isNew: true,
          );
          // Click on the Dart Debug Extension icon:
          await workerEvalDelay();
          await clickOnExtensionIcon(
            browser: browser,
            worker: worker,
            backgroundPage: backgroundPage,
          );
          // There should now be a warning notification:
          final chromeNotifications = await evaluate(
            _getNotifications(),
            worker: worker,
            backgroundPage: backgroundPage,
          );
          await workerEvalDelay();
          expect(chromeNotifications, isNotEmpty);
          // Close the tab:
          await tab.close();
        });

        test('Refreshing the Dart app does not open a new Dart DevTools',
            () async {
          final appUrl = context.appUrl;
          final devToolsUrlFragment =
              useSse ? 'debugger?uri=sse' : 'debugger?uri=ws';
          // Navigate to the Dart app:
          final appTab =
              await navigateToPage(browser, url: appUrl, isNew: true);
          // Click on the Dart Debug Extension icon:
          await workerEvalDelay();
          await clickOnExtensionIcon(
            browser: browser,
            worker: worker,
            backgroundPage: backgroundPage,
          );
          // Verify that the Dart DevTools tab is open:
          final devToolsTabTarget = await browser.waitForTarget(
            (target) => target.url.contains(devToolsUrlFragment),
          );
          expect(devToolsTabTarget.type, equals('page'));
          // Refresh the app tab:
          await appTab.reload();
          // Verify that we don't open a new Dart DevTools on page refresh:
          final devToolsTargets = browser.targets
              .where((target) => target.url.contains(devToolsUrlFragment));
          expect(devToolsTargets.length, equals(1));
          // Close the Dart app and the associated Dart DevTools:
          await appTab.close();
          await devToolsTabTarget.onClose;
        });
      });
    }

    group('connected to an externally-built', () {
      for (var isFlutterApp in [true, false]) {
        group(isFlutterApp ? 'Flutter app:' : 'Dart app:', () {
          late Browser browser;
          Worker? worker;
          Page? backgroundPage;

          setUpAll(() async {
            browser = await setUpExtensionTest(
              context,
              extensionPath: extensionPath,
              serveDevTools: true,
              isInternalBuild: false,
              isFlutterApp: isFlutterApp,
              openChromeDevTools: true,
            );

            if (isMV3) {
              worker = await getServiceWorker(browser);
            } else {
              backgroundPage = await getBackgroundPage(browser);
            }
          });

          tearDown(() async {
            await tearDownHelper(
              worker: worker,
              backgroundPage: backgroundPage,
            );
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
            final appTabId = await _getCurrentTabId(
              worker: worker,
              backgroundPage: backgroundPage,
            );
            final debugInfoKey = '$appTabId-debugInfo';
            final debugInfo = await _fetchStorageObj<DebugInfo>(
              debugInfoKey,
              storageArea: 'session',
              worker: worker,
              backgroundPage: backgroundPage,
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
              (target) => target.url.startsWith('devtools://devtools'),
            );
            chromeDevToolsTarget.type = 'page';
            final chromeDevToolsPage = await chromeDevToolsTarget.page;
            await _tabLeft(chromeDevToolsPage);
            await _takeScreenshot(
              chromeDevToolsPage,
              screenshotName: 'chromeDevTools_externalBuild',
            );
            final inspectorPanelTarget = browser.targets.firstWhereOrNull(
              (target) => target.url == 'inspector_panel',
            );
            expect(inspectorPanelTarget, isNull);
            final debuggerPanelTarget = browser.targets
                .firstWhereOrNull((target) => target.url == 'debugger_panel');
            expect(debuggerPanelTarget, isNull);
          });
        });
      }
    });

    group('connected to an internally-built', () {
      late Page appTab;

      for (var isFlutterApp in [true, false]) {
        group(isFlutterApp ? 'Flutter app:' : 'Dart app:', () {
          late Browser browser;
          Worker? worker;
          Page? backgroundPage;

          setUpAll(() async {
            browser = await setUpExtensionTest(
              context,
              extensionPath: extensionPath,
              serveDevTools: true,
              isInternalBuild: true,
              isFlutterApp: isFlutterApp,
              // TODO(elliette): Figure out if there is a way to close and then
              // re-open Chrome DevTools. That way we can test that a debug
              // session lasts across Chrome DevTools being opened and closed.
              openChromeDevTools: true,
            );
            if (isMV3) {
              worker = await getServiceWorker(browser);
            } else {
              backgroundPage = await getBackgroundPage(browser);
            }
          });

          setUp(() async {
            for (final page in await browser.pages) {
              await page.close().catchError((_) {});
            }
            appTab = await navigateToPage(
              browser,
              url: context.appUrl,
              isNew: true,
            );
          });

          tearDown(() async {
            await tearDownHelper(
              worker: worker,
              backgroundPage: backgroundPage,
            );
          });

          tearDownAll(() async {
            await browser.close();
          });
          test(
              'isFlutterApp=$isFlutterApp and isInternalBuild=true are saved in storage',
              () async {
            // Verify that we have debug info for the Dart app:
            await workerEvalDelay();
            final appTabId = await _getCurrentTabId(
              worker: worker,
              backgroundPage: backgroundPage,
            );
            final debugInfoKey = '$appTabId-debugInfo';
            final debugInfo = await _fetchStorageObj<DebugInfo>(
              debugInfoKey,
              storageArea: 'session',
              worker: worker,
              backgroundPage: backgroundPage,
            );
            expect(debugInfo.isInternalBuild, equals(true));
            expect(debugInfo.isFlutterApp, equals(isFlutterApp));
          });

          test('the correct extension panels are added to Chrome DevTools',
              () async {
            final chromeDevToolsPage = await getChromeDevToolsPage(browser);
            // There are no hooks for when a panel is added to Chrome DevTools,
            // therefore we rely on a slight delay:
            await Future.delayed(Duration(seconds: 1));
            if (isFlutterApp) {
              await _tabLeft(chromeDevToolsPage);
              final inspectorPanelElement = await _getPanelElement(
                browser,
                panel: Panel.inspector,
                elementSelector: '#panelBody',
              );
              expect(inspectorPanelElement, isNotNull);
              await _takeScreenshot(
                chromeDevToolsPage,
                screenshotName: 'inspectorPanelLandingPage_flutterApp',
              );
            }
            await _tabLeft(chromeDevToolsPage);
            final debuggerPanelElement = await _getPanelElement(
              browser,
              panel: Panel.debugger,
              elementSelector: '#panelBody',
            );
            expect(debuggerPanelElement, isNotNull);
            await _takeScreenshot(
              chromeDevToolsPage,
              screenshotName:
                  'debuggerPanelLandingPage_${isFlutterApp ? 'flutterApp' : 'dartApp'}',
            );
          });

          test('Dart DevTools is embedded for debug session lifetime',
              () async {
            final chromeDevToolsPage = await getChromeDevToolsPage(browser);
            // There are no hooks for when a panel is added to Chrome DevTools,
            // therefore we rely on a slight delay:
            await Future.delayed(Duration(seconds: 1));
            // Navigate to the Dart Debugger panel:
            await _tabLeft(chromeDevToolsPage);
            if (isFlutterApp) {
              await _tabLeft(chromeDevToolsPage);
            }
            await _clickLaunchButton(
              browser,
              panel: Panel.debugger,
            );
            // Expect the Dart DevTools IFRAME to be added:
            final devToolsUrlFragment =
                'ide=ChromeDevTools&embed=true&page=debugger';
            var iframeTarget = await browser.waitForTarget(
              (target) => target.url.contains(devToolsUrlFragment),
            );
            var iframeDestroyed = false;
            unawaited(
              iframeTarget.onClose.whenComplete(() {
                iframeDestroyed = true;
              }),
            );
            // TODO(elliette): Figure out how to reliably verify that Dart
            // DevTools has loaded, and take screenshot.
            expect(iframeTarget, isNotNull);
            // Navigate away from the Dart app:
            await appTab.goto(
              'https://dart.dev/',
              wait: Until.domContentLoaded,
            );
            // Expect the Dart DevTools IFRAME to be destroyed:
            expect(iframeDestroyed, isTrue);
            // Expect the connection lost banner to be visible:
            final connectionLostBanner = await _getPanelElement(
              browser,
              panel: Panel.debugger,
              elementSelector: '#warningBanner',
            );
            expect(connectionLostBanner, isNotNull);
            await _takeScreenshot(
              chromeDevToolsPage,
              screenshotName:
                  'debuggerPanelDisconnected_${isFlutterApp ? 'flutterApp' : 'dartApp'}',
            );
            // Navigate back to the Dart app:
            await appTab.goto(context.appUrl, wait: Until.domContentLoaded);
            // Click the launch button again
            await _clickLaunchButton(
              browser,
              panel: Panel.debugger,
            );
            // Expect the Dart DevTools IFRAME to be added again:
            iframeTarget = await browser.waitForTarget(
              (target) => target.url.contains(devToolsUrlFragment),
            );
            expect(iframeTarget, isNotNull);
          });

          // TODO(elliette): Pull TestServer out of TestContext, so we can add:
          // 1. a test case for starting another test app, loading that app in
          // the tab we were debugging, and being able to reconnect to that
          // one.
          // 2. a test case for embedding a Dart app in a tab with the same
          // origin, and being able to connect to the embedded Dart app.
          // See https://github.com/dart-lang/webdev/issues/1779

          test(
              'The Dart DevTools IFRAME has the correct query parameters and path',
              () async {
            final chromeDevToolsPage = await getChromeDevToolsPage(browser);
            // There are no hooks for when a panel is added to Chrome DevTools,
            // therefore we rely on a slight delay:
            await Future.delayed(Duration(seconds: 1));
            // Navigate to the Dart Debugger panel:
            await _tabLeft(chromeDevToolsPage);
            if (isFlutterApp) {
              await _tabLeft(chromeDevToolsPage);
            }
            await _clickLaunchButton(
              browser,
              panel: Panel.debugger,
            );
            // Expect the Dart DevTools IFRAME to be added:
            final devToolsUrlFragment =
                'ide=ChromeDevTools&embed=true&page=debugger';
            final iframeTarget = await browser.waitForTarget(
              (target) => target.url.contains(devToolsUrlFragment),
            );
            final iframeUrl = iframeTarget.url;
            // Expect the correct query parameters to be on the IFRAME url:
            final uri = Uri.parse(iframeUrl);
            final queryParameters = uri.queryParameters;
            expect(
              queryParameters.keys,
              unorderedMatches([
                'uri',
                'ide',
                'embed',
                'page',
                'backgroundColor',
              ]),
            );
            expect(queryParameters, containsPair('ide', 'ChromeDevTools'));
            expect(queryParameters, containsPair('uri', isNotEmpty));
            expect(queryParameters, containsPair('page', isNotEmpty));
            expect(
              queryParameters,
              containsPair('backgroundColor', isNotEmpty),
            );
            expect(uri.path, equals('/'));
          });

          test('Trying to debug a page with multiple Dart apps shows warning',
              () async {
            final chromeDevToolsPage = await getChromeDevToolsPage(browser);
            // There are no hooks for when a panel is added to Chrome DevTools,
            // therefore we rely on a slight delay:
            await Future.delayed(Duration(seconds: 1));
            // Navigate to the Dart Debugger panel:
            await _tabLeft(chromeDevToolsPage);
            if (isFlutterApp) {
              await _tabLeft(chromeDevToolsPage);
            }
            // Expect there to be no warning banner:
            var warningMsg = await _evaluateInPanel<String>(
              browser,
              panel: Panel.debugger,
              jsExpression: 'document.querySelector("#warningMsg").innerHTML',
            );
            expect(
              warningMsg == 'Cannot debug multiple apps in a page.',
              isFalse,
            );
            // Set the 'data-multiple-dart-apps' attribute on the DOM.
            await appTab.evaluate(_setMultipleAppsAttributeJs);
            final appTabId = await _getCurrentTabId(
              worker: worker,
              backgroundPage: backgroundPage,
            );
            // Expect multiple apps info to be saved in storage:
            final storageKey = '$appTabId-multipleAppsDetected';
            final multipleAppsDetected = await _fetchStorageObj<String>(
              storageKey,
              storageArea: 'session',
              worker: worker,
              backgroundPage: backgroundPage,
            );
            expect(multipleAppsDetected, equals('true'));
            // Expect there to be a warning banner:
            warningMsg = await _evaluateInPanel<String>(
              browser,
              panel: Panel.debugger,
              jsExpression: 'document.querySelector("#warningMsg").innerHTML',
            );
            await _takeScreenshot(
              chromeDevToolsPage,
              screenshotName:
                  'debuggerMultipleAppsDetected_${isFlutterApp ? 'flutterApp' : 'dartApp'}',
            );
            expect(
              warningMsg,
              equals('Cannot debug multiple apps in a page.'),
            );
          });
        });
      }
    });

    group('Backwards-compatible with older DWDS versions', () {
      final port = 8080;
      final hostname = 'localhost';
      final fakeAppUrl = 'http://$hostname:$port/index.html';
      final fakeAppDir = webCompatiblePath(
        p.split(
          absolutePath(
            pathFromDwds: p.join(
              'test',
              'puppeteer',
              'fake_app',
            ),
          ),
        ),
      );
      late Browser browser;
      late HttpServer server;
      Worker? worker;
      Page? backgroundPage;

      setUpAll(() async {
        server = await _fakeServer(
          hostname: hostname,
          port: port,
          assetPath: fakeAppDir,
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
        if (isMV3) {
          worker = await getServiceWorker(browser);
        } else {
          backgroundPage = await getBackgroundPage(browser);
        }
        // Navigate to the Chrome extension page instead of the blank tab
        // opened by Chrome. This is helpful for local debugging.
        final blankTab = await navigateToPage(browser, url: 'about:blank');
        await blankTab.goto('chrome://extensions/');
      });

      tearDown(() async {
        await tearDownHelper(
          worker: worker,
          backgroundPage: backgroundPage,
        );
      });

      tearDownAll(() async {
        await server.close();
        await browser.close();
      });

      // Note: This tests that the extension works for DWDS versions <17.0.0.
      // Those versions don't send the debug info with the ready event
      // (https://github.com/dart-lang/webdev/pull/1772). Therefore the values
      // are read from the Window object.
      test('reads debug info from Window and saves to storage', () async {
        // Navigate to the "Dart" app:
        final appTab =
            await navigateToPage(browser, url: fakeAppUrl, isNew: true);

        // Verify that we have debug info for the fake "Dart" app:
        final appTabId = await _getCurrentTabId(
          worker: worker,
          backgroundPage: backgroundPage,
        );
        final debugInfoKey = '$appTabId-debugInfo';
        final debugInfo = await _fetchStorageObj<DebugInfo>(
          debugInfoKey,
          storageArea: 'session',
          worker: worker,
          backgroundPage: backgroundPage,
        );
        expect(debugInfo.appId, equals('DART_APP_ID'));
        expect(debugInfo.appEntrypointPath, equals('DART_ENTRYPOINT_PATH'));
        expect(debugInfo.appInstanceId, equals('DART_APP_INSTANCE_ID'));
        expect(debugInfo.isInternalBuild, isTrue);
        expect(debugInfo.isFlutterApp, isFalse);
        expect(debugInfo.appOrigin, isNotNull);
        expect(debugInfo.appUrl, isNotNull);

        // Close the tab:
        await appTab.close();
      });

      // Note: This tests that the extension works for DWDS versions <18.0.0.
      // Those versions don't support authentication from the injected client
      // (https://github.com/dart-lang/webdev/pull/1916). Therefore the auth
      // request is sent from the extension itself.
      test('clicking on extension icon authenticates the user', () async {
        // Navigate to the "Dart" app:
        final appTab =
            await navigateToPage(browser, url: fakeAppUrl, isNew: true);

        // Wait for debug info to be saved:
        final appTabId = await _getCurrentTabId(
          worker: worker,
          backgroundPage: backgroundPage,
        );
        final debugInfoKey = '$appTabId-debugInfo';
        final debugInfo = await _fetchStorageObj<DebugInfo>(
          debugInfoKey,
          storageArea: 'session',
          worker: worker,
          backgroundPage: backgroundPage,
        );

        // Verify that the extension URL has been saved (this is what is used
        // by the extension to create the auth url):
        expect(debugInfo.extensionUrl, isNotNull);

        // Click on the extension icon:
        await clickOnExtensionIcon(
          browser: browser,
          worker: worker,
          backgroundPage: backgroundPage,
        );

        // Verify that the user is now authenticated:
        final authKey = '$appTabId-isAuthenticated';
        final isAuthenticated = await _fetchStorageObj<String>(
          authKey,
          storageArea: 'session',
          worker: worker,
          backgroundPage: backgroundPage,
        );
        expect(isAuthenticated, equals('true'));

        // Close the tab:
        await appTab.close();
      });
    });
  });
}

Future<bool> _clickLaunchButton(
  Browser browser, {
  required Panel panel,
}) async {
  try {
    final launchButton = await _getPanelElement(
      browser,
      panel: panel,
      elementSelector: '#launchDebugConnectionButton',
    );
    // Slight delay to guarantee button is clickable:
    await Future.delayed(Duration(seconds: 1));
    await launchButton!.click();
    return true;
  } catch (_) {
    return false;
  }
}

Future<Page> _getPanelPage(
  Browser browser, {
  required Panel panel,
}) async {
  final panelName =
      panel == Panel.inspector ? 'inspector_panel' : 'debugger_panel';
  var panelTarget = browser.targets
      .firstWhereOrNull((target) => target.url.contains(panelName));
  panelTarget ??=
      await browser.waitForTarget((target) => target.url.contains(panelName));
  panelTarget.type = 'page';
  return await panelTarget.page;
}

Future<T> _evaluateInPanel<T>(
  Browser browser, {
  required Panel panel,
  required String jsExpression,
}) async {
  final panelPage = await _getPanelPage(browser, panel: panel);
  final frames = panelPage.frames;
  final mainFrame = frames[0];
  return mainFrame.evaluate(jsExpression);
}

Future<ElementHandle?> _getPanelElement(
  Browser browser, {
  required Panel panel,
  required String elementSelector,
}) async {
  final panelPage = await _getPanelPage(browser, panel: panel);
  final frames = panelPage.frames;
  final mainFrame = frames[0];
  final panelElement = await mainFrame.$OrNull(elementSelector);
  return panelElement;
}

Future<void> _tabLeft(Page chromeDevToolsPage) async {
  // TODO(elliette): Detect which environment we are OS we are running
  // in and update modifier key accordingly. Meta key for MacOs and
  // Ctrl key for Linux/Windows.
  final modifierKey = Key.meta;
  await chromeDevToolsPage.keyboard.down(modifierKey);
  await chromeDevToolsPage.keyboard.press(Key.bracketLeft);
  await chromeDevToolsPage.keyboard.up(modifierKey);
}

Future<int> _getCurrentTabId({
  Worker? worker,
  Page? backgroundPage,
}) async {
  return (await evaluate(
    _currentTabIdJs,
    worker: worker,
    backgroundPage: backgroundPage,
  )) as int;
}

Future<T> _fetchStorageObj<T>(
  String storageKey, {
  required String storageArea,
  Worker? worker,
  Page? backgroundPage,
}) async {
  final json = await retryFnAsync<String>(() async {
    final storageObj = await evaluate(
      _fetchStorageObjJs(
        storageKey,
        // Only local storage exists for MV2:
        storageArea: worker != null ? storageArea : 'local',
      ),
      worker: worker,
      backgroundPage: backgroundPage,
    );
    return storageObj[storageKey];
  });
  if (T == String) return json as T;
  return serializers.deserialize(jsonDecode(json)) as T;
}

String _currentTabIdJs = '''
    async () => {
      return new Promise((resolve, reject) => {
        chrome.tabs.query({active: true, currentWindow: true}, (tabs) => {
          const tab = tabs[0];
          resolve(tab.id);
        });
      });
    }
''';

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

String _getNotifications() {
  return '''
    async () => {
      return new Promise((resolve, reject) => {
        chrome.notifications.getAll((notifications) => {
          resolve(notifications);
        });
      });
    }
''';
}

String _setMultipleAppsAttributeJs = '''
  document.documentElement.setAttribute("data-multiple-dart-apps", true);
''';

// TODO(https://github.com/dart-lang/webdev/issues/1787): Compare to golden
// images. Currently golden comparison is not set up, since this is only run
// locally, not as part of our CI test suite.
Future<void> _takeScreenshot(
  Page page, {
  required String screenshotName,
}) async {
  if (!screenshotsEnabled) return;
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

Future<HttpServer> _fakeServer({
  required String hostname,
  required int port,
  required String assetPath,
}) async {
  final server = await startHttpServer(hostname, port: port);
  final staticHandler = createStaticHandler(assetPath);
  final cascade = Cascade().add(staticHandler).add(_fakeAuthHandler);
  serveHttpRequests(server, cascade.handler, (e, s) {});
  return server;
}

Response _fakeAuthHandler(request) {
  if (request.url.path == authenticationPath) {
    return Response.ok(authenticationResponse);
  }
  return Response.notFound('Not found');
}
