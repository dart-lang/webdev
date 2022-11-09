// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';

late Target serviceWorkerTarget;
late Browser browser;

final context = TestContext();

void main() async {
  for (var useSse in [true, false]) {
    group(useSse ? 'SSE' : 'WebSockets', () {
      setUpAll(() async {
        // TODO(elliette): Only start a TestServer, that way we can get rid of
        // the launchChrome parameter: https://github.com/dart-lang/webdev/issues/1779
        await context.setUp(launchChrome: false, useSse: true);
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
      });

      tearDownAll(() async {
        await browser.close();
      });

      test('Can use the MV3 Dart Debug Extension', () async {
        final appTab = await browser.newPage();
        await appTab.goto(context.appUrl,
            wait: Until.all([Until.domContentLoaded]));
        await appTab.bringToFront();
        final worker = (await serviceWorkerTarget.worker)!;
        await worker.evaluate(clickIconJs);
        // Verify that the extension opened the Dart docs:
        final targetUrls = browser.targets.map((target) => target.url);
        expect(targetUrls, contains('https://dart.dev/'));
      });
    });
  }
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
