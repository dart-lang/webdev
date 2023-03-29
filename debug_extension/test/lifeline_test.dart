// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 12))
@Skip('https://github.com/dart-lang/webdev/issues/1788')

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import '../fixtures/context.dart';
import '../fixtures/project.dart';
import 'test_utils.dart';

void main() async {
  final provider = TestSdkConfigurationProvider();
  final context = TestContext(TestProject.testWithSoundNullSafety, provider);
  late Worker worker;
  late Browser browser;
  late String extensionPath;

  int connectionCount = 0;

  tearDownAll(provider.dispose);

  group('MV3 Debug Extension Lifeline Connection', () {
    setUpAll(() async {
      extensionPath = await buildDebugExtension(isMV3: true);
      browser = await setUpExtensionTest(
        context,
        extensionPath: extensionPath,
        serveDevTools: true,
      );
      worker = await getServiceWorker(browser);
    });

    tearDownAll(() async {
      await browser.close();
      await context.tearDown();
    });

    test('connects to a lifeline port', () async {
      // Navigate to the Dart app:
      final appTab =
          await navigateToPage(browser, url: context.appUrl, isNew: true);
      await workerEvalDelay();
      // Initiate listeners for the port connection event and the subsequent
      // reconnection logs:
      final portConnectionFuture = _connectToPort(worker);
      appTab.onConsole.listen((ConsoleMessage message) {
        final messageText = message.text ?? '';
        if (messageText
            .contains('[Dart Debug Extension] Connecting to lifeline port')) {
          connectionCount++;
        }
      });
      // Click on the Dart Debug Extension icon to intiate a debug session:
      await clickOnExtensionIcon(worker: worker, backgroundPage: null);
      final connectedToPort = await portConnectionFuture;
      // Verify that we have connected to the port:
      expect(connectedToPort, isTrue);
      expect(connectionCount, equals(1));
      // Wait for a little over 5 minutes, and verify that we have reconnected
      // to the port again:
      await _reconnectToPortDelay();
      expect(connectionCount, equals(2));
    });
  });
}

Future<void> _reconnectToPortDelay() async {
  await Future.delayed(Duration(minutes: 5) + Duration(seconds: 15));
  return;
}

Future<bool?> _connectToPort(Worker worker) async {
  return worker.evaluate<bool>(_portConnectionJs);
}

final _portConnectionJs = '''
  async () => {
    return new Promise((resolve, reject) => {
      chrome.runtime.onConnect.addListener((port) => {
        if (port.name == 'keepAlive') {
          resolve(true);
        } else {
          reject(false);
        }
      });
    });
  }
''';
