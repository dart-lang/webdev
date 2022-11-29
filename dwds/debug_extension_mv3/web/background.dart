// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:async';
import 'dart:html';

import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_types.dart';
import 'lifeline_ports.dart';
import 'logger.dart';
import 'messaging.dart';
import 'storage.dart';
import 'utils.dart';
import 'web_api.dart';

const _authSuccessResponse = 'Dart Debug Authentication Success!';

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
  chrome.tabs.onRemoved
      .addListener(allowInterop((tabId, _) => maybeRemoveLifelinePort(tabId)));
  // Update the extension icon on tab navigation:
  chrome.tabs.onActivated.addListener(allowInterop((ActiveInfo info) {
    _updateIcon(info.tabId);
  }));
  chrome.windows.onFocusChanged.addListener(allowInterop((_) async {
    final currentTab = await _getTab();
    if (currentTab?.id != null) {
      _updateIcon(currentTab!.id);
    }
  }));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop(_startDebugSession));
}

// TODO(elliette): Start a debug session instead.
Future<void> _startDebugSession(Tab currentTab) async {
  final tabId = currentTab.id;
  final debugInfo = await _fetchDebugInfo(tabId);
  final extensionUrl = debugInfo?.extensionUrl;
  if (extensionUrl == null) {
    _showWarningNotification('Can\'t debug Dart app. Extension URL not found.');
    return;
  }
  final isAuthenticated = await _authenticateUser(extensionUrl, tabId);
  if (!isAuthenticated) return;

  maybeCreateLifelinePort(currentTab.id);
  final devToolsOpener = await fetchStorageObject<DevToolsOpener>(
      type: StorageObject.devToolsOpener);
  await _createTab('https://dart.dev/',
      inNewWindow: devToolsOpener?.newWindow ?? false);
}

Future<bool> _authenticateUser(String extensionUrl, int tabId) async {
  final authUrl = _constructAuthUrl(extensionUrl).toString();
  final response = await fetchRequest(authUrl);
  final responseBody = response.body ?? '';
  if (!responseBody.contains(_authSuccessResponse)) {
    debugError('Not authenticated: ${response.status} / $responseBody', devOnly: false,);
    _showWarningNotification('Please re-authenticate and try again.');
    await _createTab(authUrl, inNewWindow: false);
    return false;
  }
  return true;
}

Uri _constructAuthUrl(String extensionUrl) {
  final authUri = Uri.parse(extensionUrl).replace(path: authenticationPath);
  if (authUri.scheme == 'ws') {
    return authUri.replace(scheme: 'http');
  }
  if (authUri.scheme == 'wss') {
    return authUri.replace(scheme: 'https');
  }
  return authUri;
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
        final dartTab = sender.tab;
        if (dartTab == null) {
          debugWarn('Received debug info but tab is missing.');
          return;
        }
        // Save the debug info for the Dart app in storage:
        await setStorageObject<DebugInfo>(
            type: StorageObject.debugInfo, value: debugInfo, tabId: dartTab.id);
        // Update the icon to show that a Dart app has been detected:
        final currentTab = await _getTab();
        if (currentTab?.id == dartTab.id) {
          _setDebuggableIcon();
        }
      });
}

void _updateIcon(int activeTabId) async {
  final debugInfo = await _fetchDebugInfo(activeTabId);
  if (debugInfo != null) {
    _setDebuggableIcon();
  } else {
    _setDefaultIcon();
  }
}

void _setDebuggableIcon() {
  chrome.action.setIcon(IconInfo(path: 'dart.png'), /*callback*/ null);
}

void _setDefaultIcon() {
  final iconPath = isDevMode() ? 'dart_dev.png' : 'dart_grey.png';
  chrome.action.setIcon(IconInfo(path: iconPath), /*callback*/ null);
}

Future<DebugInfo?> _fetchDebugInfo(int tabId) {
  return fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: tabId,
  );
}

void _showWarningNotification(String message) {
  chrome.notifications.create(
    /*notificationId*/ null,
    NotificationOptions(
      title: '[Error] Dart Debug Extension',
      message: message,
      iconUrl: 'dart.png',
      type: 'basic',
    ),
    /*callback*/ null,
  );
}

Future<Tab?> _getTab() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  return tabs.isNotEmpty ? tabs.first : null;
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
