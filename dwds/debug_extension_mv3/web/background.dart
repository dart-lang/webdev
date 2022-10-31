// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:html';

import 'package:js/js.dart';
import 'package:dwds/data/debug_info.dart';

import 'chrome_api.dart';
import 'messaging.dart';
import 'web_api.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop((_) async {
    _keepDebugSessionAlive();
    _createTab('https://www.wikipedia.org/', inNewWindow: true);
  }));
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest is! String) return;

  interceptMessage<DebugInfo>(
      message: jsRequest,
      expectedType: MessageType.debugInfo,
      expectedSender: Script.detector,
      expectedRecipient: Script.background,
      messageHandler: (DebugInfo debugInfo) async {
        final currentTab = await _getTab();
        if (currentTab == null) return;

        final currentUrl = currentTab.url;
        final appUrl = debugInfo.appUrl;
        console.log('APP URL: $appUrl');
        console.log('CURRENT URL: $currentUrl');
      });
}

Future<Tab> _createTab(String url, {bool inNewWindow = false}) async {
  if (inNewWindow) {
    final windowPromise = chrome.windows.create(
      WindowInfo(focused: true, url: url, state: 'minimized'),
    );
    final windowObj = await promiseToFuture<WindowObj>(windowPromise);
    return windowObj.tabs.first;
  }
  final tabPromise = chrome.tabs.create(TabInfo(
    active: true,
    url: url,
  ));
  return promiseToFuture<Tab>(tabPromise);
}

Future<Tab?> _getTab() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  return tabs.isNotEmpty ? tabs.first : null;
}
