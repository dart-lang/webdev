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

import 'data_types.dart';
import 'debug_session.dart';
import 'chrome_api.dart';
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
  chrome.webNavigation.onCommitted
      .addListener(allowInterop(_detectNavigationAwayFromDartApp));

  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop(
    (Tab tab) => _startDebugSession(
      tab.id,
      trigger: Trigger.extensionIcon,
    ),
  ));
}

Future<void> _startDebugSession(int tabId, {required Trigger trigger}) async {
  final debugInfo = await _fetchDebugInfo(tabId);
  final extensionUrl = debugInfo?.extensionUrl;
  if (extensionUrl == null) {
    _showWarningNotification('Can\'t debug Dart app. Extension URL not found.');
    sendConnectFailureMessage(
      ConnectFailureReason.no_dart_app,
      dartAppTabId: tabId,
    );
    return;
  }
  final isAuthenticated = await _authenticateUser(extensionUrl, tabId);
  if (!isAuthenticated) {
    sendConnectFailureMessage(
      ConnectFailureReason.authentication,
      dartAppTabId: tabId,
    );
    return;
  }

  maybeCreateLifelinePort(tabId);
  attachDebugger(tabId, trigger: trigger);
}

Future<bool> _authenticateUser(String extensionUrl, int tabId) async {
  final authUrl = _constructAuthUrl(extensionUrl).toString();
  final response = await fetchRequest(authUrl);
  final responseBody = response.body ?? '';
  if (!responseBody.contains(_authSuccessResponse)) {
    debugError('Not authenticated: ${response.status} / $responseBody',
        verbose: true);
    _showWarningNotification('Please re-authenticate and try again.');
    await createTab(authUrl, inNewWindow: false);
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

  interceptMessage<DebugStateChange>(
      message: jsRequest,
      expectedType: MessageType.debugStateChange,
      expectedSender: Script.debuggerPanel,
      expectedRecipient: Script.background,
      messageHandler: (DebugStateChange debugStateChange) {
        final newState = debugStateChange.newState;
        final tabId = debugStateChange.tabId;
        if (newState == DebugStateChange.startDebugging) {
          _startDebugSession(tabId, trigger: Trigger.extensionPanel);
        }
      });
}

void _detectNavigationAwayFromDartApp(NavigationInfo navigationInfo) async {
  final tabId = navigationInfo.tabId;
  final debugInfo = await _fetchDebugInfo(navigationInfo.tabId);
  if (debugInfo == null) return;
  if (debugInfo.appUrl != navigationInfo.url) {
    _setDefaultIcon();
    await removeStorageObject(type: StorageObject.debugInfo, tabId: tabId);
    detachDebugger(
      tabId,
      type: TabType.dartApp,
      reason: DetachReason.navigated_away_from_app,
    );
  }
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
  chrome.action
      .setIcon(IconInfo(path: 'static_assets/dart.png'), /*callback*/ null);
}

void _setDefaultIcon() {
  final iconPath = isDevMode()
      ? 'static_assets/dart_dev.png'
      : 'static_assets/dart_grey.png';
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
      iconUrl: 'static_assets/dart.png',
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
