// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(seconds: 60))
import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:webdev/src/logging.dart';
import 'package:webdev/src/serve/chrome.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

void main() {
  Chrome? chrome;

  Future<void> launchChrome({int? port, String? userDataDir}) async {
    chrome = await Chrome.start([_googleUrl],
        port: port ?? 0, userDataDir: userDataDir);
  }

  Future<void> openTab(String url) =>
      chrome!.chromeConnection.getUrl(_openTabUrl(url));

  Future<void> closeTab(ChromeTab tab) =>
      chrome!.chromeConnection.getUrl(_closeTabUrl(tab.id));

  Future<WipConnection> connectToTab(String url) async {
    var tab = await chrome!.chromeConnection.getTab((t) => t.url.contains(url));
    expect(tab, isNotNull);
    return tab!.connect();
  }

  group('chrome with temp data dir', () {
    tearDown(() async {
      var tabs = await chrome?.chromeConnection.getTabs();
      if (tabs != null) {
        for (var tab in tabs) {
          await closeTab(tab);
        }
      }
      await chrome?.close();
      chrome = null;
    });

    test('can launch chrome', () async {
      await launchChrome();
      expect(chrome, isNotNull);
    });

    test('has a working debugger', () async {
      await launchChrome();
      var tabs = await chrome!.chromeConnection.getTabs();
      expect(
          tabs,
          contains(const TypeMatcher<ChromeTab>()
              .having((t) => t.url, 'url', _googleUrl)));
    });

    test('uses open debug port if provided port is 0', () async {
      await launchChrome(port: 0);
      expect(chrome!.debugPort, isNot(equals(0)));
    });

    test('has correct profile path', () async {
      await launchChrome();
      await openTab(_chromeVersionUrl);

      var wipConnection = await connectToTab(_chromeVersionUrl);
      var result = await _evaluateExpression(wipConnection.page,
          "document.getElementById('profile_path').textContent");

      if (Platform.isWindows) {
        // --user-data-dir is not supported on Windows yet
        // Issue: https://github.com/dart-lang/webdev/issues/1545
        expect(result, isNot(contains('chrome_user_data')));
      } else {
        expect(result, contains('chrome_user_data'));
      }
    });
  });

  group('chrome with user data dir', () {
    late Directory dataDir;
    late StreamController<String> logController;
    late Stream<String> logStream;

    setUp(() {
      logController = StreamController<String>();
      logStream = logController.stream;

      void _logWriter(Level level, String message,
          {String? error, String? loggerName, String? stackTrace}) {
        if (level >= Level.INFO) {
          logController.add('[$level] $loggerName: $message');
        }
      }

      configureLogWriter(true, customLogWriter: _logWriter);
      dataDir = Directory.systemTemp.createTempSync(_userDataDirName);
    });

    tearDown(() async {
      var tabs = await chrome?.chromeConnection.getTabs();
      if (tabs != null) {
        for (var tab in tabs) {
          await closeTab(tab);
        }
      }
      await chrome?.close();
      chrome = null;

      // Issue: https://github.com/dart-lang/webdev/issues/1545
      if (!Platform.isWindows) {
        expect(
            logStream,
            emitsThrough(matches('Starting chrome with user data directory:'
                '.*chrome_user_data_copy')));
        await logController.close();
      }
      dataDir.deleteSync(recursive: true);
    });

    test('works with debug port', () async {
      await launchChrome(userDataDir: dataDir.path);
      expect(chrome, isNotNull);
    });

    test('has a working debugger', () async {
      await launchChrome(userDataDir: dataDir.path);

      var tabs = await chrome!.chromeConnection.getTabs();
      expect(
          tabs,
          contains(const TypeMatcher<ChromeTab>()
              .having((t) => t.url, 'url', _googleUrl)));
    });

    test('has correct profile path', () async {
      await launchChrome(userDataDir: dataDir.path);
      await openTab(_chromeVersionUrl);

      var wipConnection = await connectToTab(_chromeVersionUrl);
      var result = await _evaluateExpression(wipConnection.page,
          "document.getElementById('profile_path').textContent");

      if (Platform.isWindows) {
        // --user-data-dir is not supported on Windows yet
        // Issue: https://github.com/dart-lang/webdev/issues/1545
        expect(result, isNot(contains('chrome_user_data_copy')));
      } else {
        expect(result, contains('chrome_user_data_copy'));
      }
    });

    test('can auto detect default chrome directory', () async {
      var userDataDir = autoDetectChromeUserDataDirectory();
      expect(userDataDir, isNotNull);

      expect(Directory(userDataDir!).existsSync(), isTrue);

      await launchChrome(userDataDir: userDataDir);
      await openTab(_chromeVersionUrl);

      var wipConnection = await connectToTab(_chromeVersionUrl);
      var result = await _evaluateExpression(wipConnection.page,
          "document.getElementById('profile_path').textContent");

      expect(result, contains('chrome_user_data_copy'));
    }, onPlatform: {
      'windows': const Skip('https://github.com/dart-lang/webdev/issues/1545')
    });

    test('cannot auto detect default chrome directory on windows', () async {
      var userDataDir = autoDetectChromeUserDataDirectory();
      expect(userDataDir, isNull);
    }, onPlatform: {
      'linux': const Skip('https://github.com/dart-lang/webdev/issues/1545'),
      'mac-os': const Skip('https://github.com/dart-lang/webdev/issues/1545'),
    });
  });
}

String _openTabUrl(String url) => '/json/new?$url';
String _closeTabUrl(String id) => '/json/close/$id';

Future<String> _evaluateExpression(WipPage page, String expression) async {
  String? result = '';
  while (result == null || result.isEmpty) {
    await Future.delayed(const Duration(milliseconds: 100));
    var wipResponse = await page.sendCommand(
      'Runtime.evaluate',
      params: {'expression': expression},
    );
    result = wipResponse.json['result']['result']['value'] as String?;
  }
  return result;
}

const _googleUrl = 'https://www.google.com/';
const _chromeVersionUrl = 'chrome://version/';
const _userDataDirName = 'data dir';
