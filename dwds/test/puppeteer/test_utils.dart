// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

Future<String> buildDebugExtension() async {
  final currentDir = Directory.current.path;
  if (!currentDir.endsWith('dwds')) {
    throw StateError(
        'Expected to be in /dwds directory, instead path was $currentDir.');
  }
  final extensionDir = p.join(currentDir, 'debug_extension_mv3');
  // TODO(elliette): This doesn't work on Windows, see https://github.com/dart-lang/webdev/issues/1724.
  await Process.run(
    p.join('tool', 'build_extension.sh'),
    [],
    workingDirectory: extensionDir,
  );
  return '$extensionDir/compiled';
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

final clickIconJs = '''
  async () => {
    const activeTabs = await chrome.tabs.query({ active: true });
    const tab = activeTabs[0];
    chrome.action.onClicked.dispatch(tab);
  }
''';
