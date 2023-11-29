// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';
import 'package:test_common/utilities.dart';

import '../fixtures/context.dart';
import '../fixtures/utilities.dart';

enum ConsoleSource {
  background,
  devTools,
  worker,
}

final _backgroundLogs = [];
final _devToolsLogs = [];
final _workerLogs = [];

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
  String? workspaceName,
}) async {
  // TODO(elliette): Only start a TestServer, that way we can get rid of the
  // launchChrome parameter: https://github.com/dart-lang/webdev/issues/1779
  await context.setUp(
    testSettings: TestSettings(
      launchChrome: false,
      isFlutterApp: isFlutterApp,
    ),
    appMetadata: TestAppMetadata(
      isInternalBuild: isInternalBuild,
      workspaceName: workspaceName,
    ),
    debugSettings: serveDevTools
        ? TestDebugSettings.withDevTools(context).copyWith(
            enableDebugExtension: true,
            useSse: useSse,
          )
        : TestDebugSettings.noDevTools().copyWith(
            enableDebugExtension: true,
            useSse: useSse,
          ),
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

Future<void> tearDownHelper({
  Worker? worker,
  Page? backgroundPage,
}) async {
  _logConsoleMsgsOnFailure();
  _backgroundLogs.clear();
  _workerLogs.clear();
  _devToolsLogs.clear();
  await _clearStorage(
    worker: worker,
    backgroundPage: backgroundPage,
  );
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
        _saveConsoleMsg(
          source: ConsoleSource.worker,
          type: '$type',
          msg: '$handle',
        );
      }
    },
    onExceptionThrown: null,
  );
}

Future<Page> getBackgroundPage(Browser browser) async {
  final backgroundPageTarget =
      await browser.waitForTarget((target) => target.type == 'background_page');
  final backgroundPage = await backgroundPageTarget.page;
  backgroundPage.onConsole.listen((msg) {
    _saveConsoleMsg(
      source: ConsoleSource.background,
      type: '${msg.type}',
      msg: msg.text ?? '',
    );
  });
  return backgroundPage;
}

Future<Page> getChromeDevToolsPage(Browser browser) async {
  final chromeDevToolsTarget = browser.targets
      .firstWhere((target) => target.url.startsWith('devtools://devtools'));
  chromeDevToolsTarget.type = 'page';
  final chromeDevToolsPage = await chromeDevToolsTarget.page;
  chromeDevToolsPage.onConsole.listen((msg) {
    _saveConsoleMsg(
      source: ConsoleSource.devTools,
      type: '${msg.type}',
      msg: msg.text ?? '',
    );
  });
  return chromeDevToolsPage;
}

Future evaluate(
  String jsExpression, {
  Worker? worker,
  Page? backgroundPage,
}) async {
  if (worker != null) {
    assert(backgroundPage == null);
    return worker.evaluate(jsExpression);
  } else {
    return backgroundPage!.evaluate(jsExpression);
  }
}

Future<void> clickOnExtensionIcon({
  required Browser browser,
  Worker? worker,
  Page? backgroundPage,
}) async {
  await evaluate(
    _clickIconJs(isMV3: worker != null),
    worker: worker,
    backgroundPage: backgroundPage,
  );
  final popupTarget = await browser.waitForTarget(
    (target) => target.url.contains('popup'),
  );
  final popupPage = await popupTarget.page;
  final launchDevToolsButton = await popupPage.$OrNull('#launchDevToolsButton');
  await launchDevToolsButton?.click();
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

void _saveConsoleMsg({
  required ConsoleSource source,
  required String type,
  required String msg,
}) {
  if (msg.isEmpty) return;
  final conciseMsg = msg.startsWith('JSHandle:') ? msg.substring(9) : msg;
  final formatted = 'console.$type: $conciseMsg';
  switch (source) {
    case ConsoleSource.background:
      _backgroundLogs.add(formatted);
      break;
    case ConsoleSource.devTools:
      _devToolsLogs.add(formatted);
      break;
    case ConsoleSource.worker:
      _workerLogs.add(formatted);
      break;
  }
}

void _logConsoleMsgsOnFailure() {
  if (_backgroundLogs.isNotEmpty) {
    printOnFailure(['Background Page logs:', ..._backgroundLogs].join('\n'));
  }
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

Future<void> _clearStorage({
  Worker? worker,
  Page? backgroundPage,
}) async {
  return evaluate(
    _clearStorageJs(isMV3: worker != null),
    worker: worker,
    backgroundPage: backgroundPage,
  ).catchError((_) {});
}

String _clickIconJs({bool isMV3 = false}) => '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true }, (tabs) => {
      const tab = tabs[0];
      chrome.${isMV3 ? 'action' : 'browserAction'}.onClicked.dispatch(tab);
    });
  }
''';

String _clearStorageJs({required bool isMV3}) => '''
    async () => {
      await chrome.storage.local.clear();
      ${isMV3 ? 'await chrome.storage.session.clear();' : ''}
      return true;
    }
''';
