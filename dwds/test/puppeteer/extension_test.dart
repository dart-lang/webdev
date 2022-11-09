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
        print('starting test');
        final appTab = await browser.newPage();
        await appTab.goto(context.appUrl, wait: Until.domContentLoaded);
        await appTab.bringToFront();

                print('APP BROWSER CONTEXT IS:');
       //  print(appTab.target.browser.);
        final worker = (await serviceWorkerTarget.worker)!;
        await worker.evaluate(clickIconJs);
        // Verify that the extension opened the Dart docs:
        final openedTabTarget = await browser.waitForTarget(
            (target) => target.url.contains('https://dart.dev/'));

        print('OPENED TAB CONTEXT IS:');
        print(openedTabTarget.browserContext.id);
        expect(openedTabTarget, isNotNull);
        expect(openedTabTarget.isPage, isTrue);
        final openedTab = await openedTabTarget.page;
        await openedTab.close();

        final extensionOrigin = getExtensionOrigin(browser);
        final settingsTab = await browser.newPage();
        await settingsTab.goto('$extensionOrigin/settings.html',
            wait: Until.domContentLoaded);
        await settingsTab.bringToFront();
        expect(settingsTab.url, contains('settings.html'));
        await Future.delayed(Duration(seconds: 2));
        await settingsTab.tap('#windowOpt');
        await Future.delayed(Duration(seconds: 2));
        await settingsTab.tap('#saveButton');
        await Future.delayed(Duration(seconds: 2));
        await appTab.goto(context.appUrl, wait: Until.domContentLoaded);
        await appTab.bringToFront();
        await Future.delayed(Duration(seconds: 2));
        await worker.evaluate(clickIconJs);
        final openedWindowTarget = await browser.waitForTarget(
            (target) => target.url.contains('https://dart.dev/'));

        await Future.delayed(Duration(seconds: 2));
        
        expect(openedWindowTarget, isNotNull);
        print('opened window is a:');
        print(openedWindowTarget.type);
        expect(openedWindowTarget.isPage, isTrue, reason: 'Not a page.');
        print('OPEN WINDOW BROWSER CONTEXT IS:');
        print(openedWindowTarget.browserContext.id);


        // final openedWindow = await openedTabTarget.page;
        // await openedWindow.close();
      });
    });
  }
}

Iterable<String> getUrlsInBrowser(Browser browser) {
  return browser.targets.map((target) => target.url);
}

String getExtensionOrigin(Browser browser) {
  final chromeExtension = 'chrome-extension:';
  final extensionUrl = getUrlsInBrowser(browser)
      .firstWhere((url) => url.contains(chromeExtension));
  final urlSegments = p.split(extensionUrl);
  final extensionId = urlSegments[urlSegments.indexOf(chromeExtension) + 1];
  return '$chromeExtension//$extensionId';
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
