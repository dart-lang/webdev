// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';
import '../fixtures/utilities.dart';

enum ConsoleSource {
  worker,
  devTools,
}

final _workerLogs = [];
final _devToolsLogs = [];

Future<String> buildDebugExtension({required bool isMV3}) async {
  final extensionDir = absolutePath(pathFromDwds: 'debug_extension_mv3');
  await Process.run(
    'dart',
    [
      p.join('tool', 'build_extension.dart'),
      if (isMV3) '--mv3',
    ],
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

Future<void> tearDownHelper({required Worker worker}) async {
  _logConsoleMsgsOnFailure();
  _workerLogs.clear();
  _devToolsLogs.clear();
  await worker.evaluate(_clearStorageJs).catchError((_) {});
}

Future<Worker> getServiceWorker(Browser browser) async {
  final serviceWorkerTarget =
      await browser.waitForTarget((target) => target.type == 'service_worker');
  final worker = (await serviceWorkerTarget.worker)!;
  return Worker(
    worker.client,
    worker.url,
    onConsoleApiCalled: (type, jsHandles, _) {
      for (var handle in jsHandles) {
        saveConsoleMsg(
            source: ConsoleSource.worker, type: '$type', msg: '$handle');
      }
    },
    onExceptionThrown: null,
  );
}

Future<Page> getChromeDevToolsPage(Browser browser) async {
  final chromeDevToolsTarget = browser.targets
      .firstWhere((target) => target.url.startsWith('devtools://devtools'));
  chromeDevToolsTarget.type = 'page';
  final chromeDevToolsPage = await chromeDevToolsTarget.page;
  chromeDevToolsPage.onConsole.listen((msg) {
    saveConsoleMsg(
      source: ConsoleSource.devTools,
      type: '${msg.type}',
      msg: msg.text ?? '',
    );
  });
  return chromeDevToolsPage;
}

void saveConsoleMsg({
  required ConsoleSource source,
  required String type,
  required String msg,
}) {
  if (msg.isEmpty) return;
  final consiseMsg = msg.startsWith('JSHandle:') ? msg.substring(9) : msg;
  final formatted = 'console.$type: $consiseMsg';
  switch (source) {
    case ConsoleSource.worker:
      _workerLogs.add(formatted);
      break;
    case ConsoleSource.devTools:
      _devToolsLogs.add(formatted);
      break;
  }
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

void _logConsoleMsgsOnFailure() {
  if (_workerLogs.isNotEmpty) {
    printOnFailure(['Service Worker logs:', ..._workerLogs].join('\n'));
  }
  if (_devToolsLogs.isNotEmpty) {
    printOnFailure(['Chrome DevTools logs:', ..._devToolsLogs].join('\n'));
  }
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

final _clearStorageJs = '''
    async () => {
      await chrome.storage.local.clear();
      await chrome.storage.session.clear();
      return true;
    }
''';
