// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:html';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';
import 'web_api.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop(_startDebugSession));
}

void _startDebugSession(Tab _) async {
  // TODO(elliette): Start a debug session instead.
  _createTab('https://dart.dev/');
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
        final currentUrl = currentTab?.url ?? '';
        final appUrl = debugInfo.appUrl ?? '';
        if (currentUrl.isEmpty || appUrl.isEmpty || currentUrl != appUrl) {
          console.warn(
              'Dart app detected at $appUrl but current tab is $currentUrl.');
          return;
        }
        // Update the icon to show that a Dart app has been detected:
        chrome.action.setIcon(IconInfo(path: 'dart.png'), /*callback*/ null);
      });
}

Future<Tab?> _getTab() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  return tabs.isNotEmpty ? tabs.first : null;
}

Future<Tab> _createTab(String url) async {
  final tabPromise = chrome.tabs.create(TabInfo(
    active: true,
    url: url,
  ));
  return promiseToFuture<Tab>(tabPromise);
}
