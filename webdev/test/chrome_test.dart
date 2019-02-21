// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';
import 'package:webdev/src/serve/chrome.dart';

void main() {
  Chrome chrome;
  setUp(() async {
    // The url doesn't matter.
    chrome = await Chrome.start(['www.google.com']);
  });

  tearDown(() {
    chrome?.close();
    chrome = null;
  });

  test('can launch chrome', () async {
    expect(chrome, isNotNull);
  }, skip: Platform.isWindows);

  test('debugger is working', () async {
    var tabs = await chrome.chromeConnection.getTabs();
    expect(tabs.length, equals(1));
  }, skip: Platform.isWindows);
}
