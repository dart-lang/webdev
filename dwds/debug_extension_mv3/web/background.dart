// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:async';
import 'dart:html';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_types.dart';
import 'lifeline_ports.dart';
import 'messaging.dart';
import 'storage.dart';
import 'web_api.dart';

/// Switch to true for debug logging.
bool enableDebugLogging = false;

final dartAppTabs = <Tab>[];
int? currentLifelineTab;


void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop(_startDebugSession));
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
        final appUrl = debugInfo.appUrl ?? '';
        if (currentUrl.isEmpty || appUrl.isEmpty || currentUrl != appUrl) {
          console.warn(
              'Dart app detected at $appUrl but current tab is $currentUrl.');
        } else {
          // Update the icon to show that a Dart app has been detected:
          chrome.action.setIcon(IconInfo(path: 'dart.png'), /*callback*/ null);
        }
        setStorageObject<DebugInfo>(
          type: StorageObject.debugInfo,
          value: debugInfo,
          tabId: currentTab.id,
        );
      });
}

void _startDebugSession(Tab currentTab) async {
  dartAppTabs.add(currentTab);
  // final debugInfo = await fetchStorageObject(
  //   type: StorageObject.debugInfo,
  //   tabId: currentTab.id,
  // );
  // if (debugInfo == null) {
  //   console.warn('Current tab is not a debuggable Dart app');
  //   return;
  // }

  final portTab = createLifelinePortForTab(currentTab.id);
  if (portTab != null) {
    currentLifelineTab = portTab;
  }

  // TODO(elliette): Start a debug session instead.
  final devToolsOpener = await fetchStorageObject<DevToolsOpener>(
      type: StorageObject.devToolsOpener);
  _createTab('https://dart.dev/',
      inNewWindow: devToolsOpener?.newWindow ?? false);
}

Future<Tab> _createTab(String url, {bool inNewWindow = false}) async {
  if (inNewWindow) {
    final windowPromise = chrome.windows.create(
      WindowInfo(focused: true, url: url),
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
