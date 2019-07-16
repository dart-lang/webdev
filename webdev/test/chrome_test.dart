// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:test/test.dart';
import 'package:webdev/src/serve/chrome.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

void main() {
  Chrome chrome;

  Future<void> launchChrome({int port}) async {
    chrome = await Chrome.start([_googleUrl], port: port);
  }

  tearDown(() async {
    await chrome?.close();
    chrome = null;
  });

  test('can launch chrome', () async {
    await launchChrome();
    expect(chrome, isNotNull);
  });

  test('debugger is working', () async {
    await launchChrome();
    var tabs = await chrome.chromeConnection.getTabs();
    expect(
        tabs,
        contains(const TypeMatcher<ChromeTab>()
            .having((t) => t.url, 'url', _googleUrl)));
  });

  test('uses open debug port if provided port is 0', () async {
    await launchChrome(port: 0);
    expect(chrome.debugPort, isNot(equals(0)));
  });
}

const _googleUrl = 'http://www.google.com/';
