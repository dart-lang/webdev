// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:test/test.dart';

import 'fixtures/context.dart';

// [For Googlers]
// A whitelisted developer key is needed to run these tests locally.
// Add a developer key to dwds/debug_extension/web/manifest.json.
// Otherwise, you will get 'Error Loading Extension' alert.
// Remove the key before pushing code to GitHub.
// See go/extension-identification.

final context = TestContext();
void main() async {
  setUpAll(() async {
    await context.setUp(enableDebugExtension: true);
    await context.extensionConnection.sendCommand('Runtime.evaluate', {
      'expression': 'fakeClick()',
    });
    // Wait for DevTools to actually open.
    await Future.delayed(const Duration(seconds: 2));
  });

  tearDownAll(() async {
    await context.tearDown();
  });

  test('can launch DevTools', () async {
    var windows = await context.webDriver.windows.toList();
    await context.webDriver.driver.switchTo.window(windows.last);
    expect(await context.webDriver.title, 'Dart DevTools');
  });

  test('can close DevTools and relaunch', () async {
    await (await context.webDriver.windows.toList()).last.close();

    // Relaunch DevTools by (fake) clicking the extension.
    await context.extensionConnection.sendCommand('Runtime.evaluate', {
      'expression': 'fakeClick()',
    });
    await Future.delayed(const Duration(seconds: 2));
    var windows = await context.webDriver.windows.toList();
    await context.webDriver.driver.switchTo.window(windows.last);
    expect(await context.webDriver.title, 'Dart DevTools');
  });
}
