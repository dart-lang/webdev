// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

import '../fixtures/context.dart';
import '../fixtures/utilities.dart';

Future<String> buildDebugExtension() async {
  final extensionDir = absolutePath(pathFromDwds: 'debug_extension_mv3');
  // TODO(elliette): This doesn't work on Windows, see https://github.com/dart-lang/webdev/issues/1724.
  await Process.run(
    p.join('tool', 'build_extension.sh'),
    [],
    workingDirectory: extensionDir,
  );
  return p.join(extensionDir, 'compiled');
}

Future<Browser> setUpExtensionTest(
  TestContext context, {
  required String extensionPath,
  bool serveDevTools = true,
  bool useSse = false,
  bool isInternalBuild = false,
  bool isFlutterApp = false,
  bool openChromeDevTools = false,
}) async {
  // TODO(elliette): Only start a TestServer, that way we can get rid of the
  // launchChrome parameter: https://github.com/dart-lang/webdev/issues/1779
  await context.setUp(
    launchChrome: false,
    serveDevTools: serveDevTools,
    useSse: useSse,
    enableDebugExtension: true,
    isInternalBuild: isInternalBuild,
    isFlutterApp: isFlutterApp,
  );
  return await puppeteer.launch(
    devTools: openChromeDevTools,
    headless: false,
    timeout: Duration(seconds: 60),
    args: [
      '--load-extension=$extensionPath',
      '--disable-extensions-except=$extensionPath',
      '--disable-features=DialMediaRouteProvider',
    ],
  );
}

Future<Worker> getServiceWorker(Browser browser) async {
  final serviceWorkerTarget =
      await browser.waitForTarget((target) => target.type == 'service_worker');
  return (await serviceWorkerTarget.worker)!;
}

Future<void> clickOnExtensionIcon(Worker worker) async {
  return worker.evaluate(_clickIconJs);
}

// Note: The following delay is required to reduce flakiness. It makes
// sure the service worker execution context is ready.
Future<void> workerEvalDelay() async {
  await Future.delayed(Duration(seconds: 1));
  return;
}

Future<Page> navigateToPage(
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

String getExtensionOrigin(Browser browser) {
  final chromeExtension = 'chrome-extension:';
  final extensionUrl = _getUrlsInBrowser(browser)
      .firstWhere((url) => url.contains(chromeExtension));
  final urlSegments = p.split(extensionUrl);
  final extensionId = urlSegments[urlSegments.indexOf(chromeExtension) + 1];
  return '$chromeExtension//$extensionId';
}

Iterable<String> _getUrlsInBrowser(Browser browser) {
  return browser.targets.map((target) => target.url);
}

Future<Page> _getPageForUrl(Browser browser, {required String url}) {
  final pageTarget = browser.targets.firstWhere((target) => target.url == url);
  return pageTarget.page;
}

final _clickIconJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    chrome.action.onClicked.dispatch(tab);
  }
''';
