// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:async';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'cross_extension_communication.dart';
import 'data_types.dart';
import 'debug_session.dart';
import 'logger.dart';
import 'messaging.dart';
import 'storage.dart';
import 'utils.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(
    allowInterop(_handleRuntimeMessages),
  );
  // The only extension allowed to send messages to this extension is the
  // AngularDart DevTools extension. Its permission is set in the manifest.json
  // externally_connectable field.
  chrome.runtime.onMessageExternal.addListener(
    allowInterop(handleMessagesFromAngularDartDevTools),
  );
  // Update the extension icon on tab navigation:
  chrome.tabs.onActivated.addListener(allowInterop((ActiveInfo info) {
    _updateIcon(info.tabId);
  }));
  chrome.windows.onFocusChanged.addListener(allowInterop((_) async {
    final currentTab = await activeTab;
    if (currentTab?.id != null) {
      _updateIcon(currentTab!.id);
    }
  }));
  chrome.webNavigation.onCommitted
      .addListener(allowInterop(_detectNavigationAwayFromDartApp));

  // Detect clicks on the Dart Debug Extension icon.
  onExtensionIconClicked(allowInterop(
    (Tab tab) => attachDebugger(
      tab.id,
      trigger: Trigger.extensionIcon,
    ),
  ));
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest is! String) return;

  interceptMessage<String>(
      message: jsRequest,
      expectedType: MessageType.isAuthenticated,
      expectedSender: Script.detector,
      expectedRecipient: Script.background,
      messageHandler: (String isAuthenticated) async {
        final dartTab = sender.tab;
        if (dartTab == null) {
          debugWarn('Received auth info but tab is missing.');
          return;
        }
        // Save the authentication info in storage:
        await setStorageObject<String>(
          type: StorageObject.isAuthenticated,
          value: isAuthenticated,
          tabId: dartTab.id,
        );
      });

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
        // If this is a new Dart app, we need to clear old debug session data:
        if (!await _matchesAppInStorage(debugInfo.appId, tabId: dartTab.id)) {
          await clearStaleDebugSession(dartTab.id);
        }
        // Save the debug info for the Dart app in storage:
        await setStorageObject<DebugInfo>(
            type: StorageObject.debugInfo, value: debugInfo, tabId: dartTab.id);
        // Update the icon to show that a Dart app has been detected:
        final currentTab = await activeTab;
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
          attachDebugger(tabId, trigger: Trigger.extensionPanel);
        }
      });
}

void _detectNavigationAwayFromDartApp(NavigationInfo navigationInfo) async {
  final tabId = navigationInfo.tabId;
  final debugInfo = await _fetchDebugInfo(navigationInfo.tabId);
  if (debugInfo == null) return;
  if (debugInfo.appUrl != navigationInfo.url) {
    _setDefaultIcon();
    await clearStaleDebugSession(tabId);
    await removeStorageObject(type: StorageObject.debugInfo, tabId: tabId);
    await detachDebugger(
      tabId,
      type: TabType.dartApp,
      reason: DetachReason.navigatedAwayFromApp,
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
  setExtensionIcon(IconInfo(path: 'static_assets/dart.png'));
}

void _setDefaultIcon() {
  final iconPath =
      isDevMode ? 'static_assets/dart_dev.png' : 'static_assets/dart_grey.png';
  setExtensionIcon(IconInfo(path: iconPath));
}

Future<DebugInfo?> _fetchDebugInfo(int tabId) {
  return fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: tabId,
  );
}

Future<bool> _matchesAppInStorage(String? appId, {required int tabId}) async {
  final debugInfo = await _fetchDebugInfo(tabId);
  return appId != null && appId == debugInfo?.appId;
}
