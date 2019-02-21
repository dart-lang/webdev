// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:webdev/src/serve/chrome.dart';

const _googleUrl = 'http://www.google.com/';

void main() {
  Chrome chrome;
  setUp(() async {
    // The url doesn't matter.
    chrome = await Chrome.start([_googleUrl]);
  });

  tearDown(() async {
    await chrome?.close();
    chrome = null;
  });

  test('can launch chrome', () async {
    expect(chrome, isNotNull);
  }, skip: Platform.isWindows);

  test('debugger is working', () async {
    var tabs = await chrome.chromeConnection.getTabs();
    expect(tabs.firstWhere((tab) => tab.url == _googleUrl), isNotNull);
  }, skip: Platform.isWindows);
}
