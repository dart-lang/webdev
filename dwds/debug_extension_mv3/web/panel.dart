// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debugger_panel;

import 'dart:convert';
import 'dart:html';

import 'package:js/js.dart';
import 'package:dwds/data/debug_info.dart';

import 'chrome_api.dart';
import 'data_types.dart';
import 'messaging.dart';
import 'data_serializers.dart';
import 'logger.dart';
import 'debug_session.dart';
import 'storage.dart';
// Show banner is no longer a dart app, and disable launch button.

bool connecting = false;
String devToolsBackgroundColor = darkColor;
bool isDartApp = true;

const bugLinkId = 'bugLink';
const darkColor = '202125';
const darkThemeClass = 'dark-theme';
const hiddenClass = 'hidden';
const iframeContainerId = 'iframeContainer';
const landingPageId = 'landingPage';
const launchDebugConnectionButtonId = 'launchDebugConnectionButton';
const lightColor = 'ffffff';
const lightThemeClass = 'light-theme';
const loadingSpinnerId = 'loadingSpinner';
const panelAttribute = 'data-panel';
const panelBodyId = 'panelBody';
const showClass = 'show';
const warningBannerId = 'warningBanner';
const warningMsgId = 'warningMsg';

void main() {
  _registerListeners();
  _setColorThemeToMatchChromeDevTools();
  _maybeUpdateFileABugLink();
}

void _registerListeners() {
  chrome.storage.onChanged.addListener(allowInterop(_handleDebugInfoChanges));
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
  final launchDebugConnectionButton =
      document.getElementById(launchDebugConnectionButtonId) as ButtonElement;
  launchDebugConnectionButton.addEventListener('click', _launchDebugConnection);
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest is! String) return;
  final tabId = chrome.devtools.inspectedWindow.tabId;
  interceptMessage<DevToolsUrl>(
      message: jsRequest,
      expectedType: MessageType.devToolsUrl,
      expectedSender: Script.background,
      expectedRecipient: Script.debuggerPanel,
      messageHandler: (DevToolsUrl devToolsUrl) async {
        if (devToolsUrl.tabId != tabId) {
          debugWarn(
              'Received DevTools URL, but Dart app tab does not match current tab.');
          return;
        }
        connecting = false;
        _injectDevToolsIframe(devToolsUrl.url);
      });

  interceptMessage<DebugStateChange>(
      message: jsRequest,
      expectedType: MessageType.debugStateChange,
      expectedSender: Script.background,
      expectedRecipient: Script.debuggerPanel,
      messageHandler: (DebugStateChange debugStateChange) async {
        if (debugStateChange.tabId != tabId) {
          debugWarn(
              'Received debug state change request, but Dart app tab does not match current tab.');
          return;
        }
        if (debugStateChange.newState == DebugStateChange.stopDebugging) {
          _handleDebugConnectionLost(debugStateChange.reason);
        }
      });

  interceptMessage<ConnectFailure>(
      message: jsRequest,
      expectedType: MessageType.connectFailure,
      expectedSender: Script.background,
      expectedRecipient: Script.debuggerPanel,
      messageHandler: (ConnectFailure connectFailure) async {
        debugLog(
            'Received connect failure for ${connectFailure.tabId} vs $tabId');
        if (connectFailure.tabId != tabId) {
          return;
        }
        connecting = false;
        _handleConnectFailure(
          ConnectFailureReason.fromString(connectFailure.reason ?? 'unknown'),
        );
      });
}

void _handleDebugInfoChanges(Object _, String storageArea) async {
  if (storageArea != 'session') return;
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: chrome.devtools.inspectedWindow.tabId,
  );
  if (debugInfo == null && isDartApp) {
    isDartApp = false;
    _showWarningBanner('Dart app is no longer open.');
  }
  if (debugInfo != null && !isDartApp) {
    isDartApp = true;
    _hideWarningBanner();
  }
}

void _maybeUpdateFileABugLink() async {
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: chrome.devtools.inspectedWindow.tabId,
  );
  final isInternal = debugInfo?.isInternalBuild ?? false;
  if (isInternal) {
    final bugLink = document.getElementById(bugLinkId);
    if (bugLink == null) return;
    bugLink.setAttribute(
        'href', 'http://b/issues/new?component=775375&template=1369639');
  }
}

void _setColorThemeToMatchChromeDevTools() async {
  final chromeTheme = chrome.devtools.panels.themeName;
  final panelBody = document.getElementById(panelBodyId);
  if (chromeTheme == 'dark') {
    devToolsBackgroundColor = darkColor;
    _updateColorThemeForElement(panelBody, isDarkTheme: true);
  } else {
    devToolsBackgroundColor = lightColor;
    _updateColorThemeForElement(panelBody, isDarkTheme: false);
  }
}

void _updateColorThemeForElement(
  Element? element, {
  required bool isDarkTheme,
}) {
  if (element == null) return;
  final classToRemove = isDarkTheme ? lightThemeClass : darkThemeClass;
  if (element.classes.contains(classToRemove)) {
    element.classes.remove(classToRemove);
    final classToAdd = isDarkTheme ? darkThemeClass : lightThemeClass;
    element.classes.add(classToAdd);
  }
}

void _handleDebugConnectionLost(String? reason) {
  final detachReason = DetachReason.fromString(reason ?? 'unknown');
  _removeDevToolsIframe();
  _updateElementVisibility(landingPageId, visible: true);
  if (detachReason != DetachReason.canceledByUser) {
    _showWarningBanner('Lost connection.');
  }
}

void _handleConnectFailure(ConnectFailureReason reason) {
  switch (reason) {
    case ConnectFailureReason.authentication:
      _showWarningBanner('Please re-authenticate and try again.');
      break;
    case ConnectFailureReason.noDartApp:
      _showWarningBanner('No Dart app detected.');
      break;
    case ConnectFailureReason.timeout:
      _showWarningBanner('Connection timed out.');
      break;
    default:
      _showWarningBanner('Failed to connect, please try again.');
  }
  _updateElementVisibility(launchDebugConnectionButtonId, visible: true);
  _updateElementVisibility(loadingSpinnerId, visible: false);
}

void _showWarningBanner(String message) {
  final warningMsg = document.getElementById(warningMsgId);
  warningMsg?.setInnerHtml(message);
  print(warningMsg);
  final warningBanner = document.getElementById(warningBannerId);
  warningBanner?.classes.add(showClass);
}

void _hideWarningBanner() {
  final warningBanner = document.getElementById(warningBannerId);
  warningBanner?.classes.remove(showClass);
}

void _launchDebugConnection(Event _) async {
  _updateElementVisibility(launchDebugConnectionButtonId, visible: false);
  _updateElementVisibility(loadingSpinnerId, visible: true);
  final dartAppTabId = chrome.devtools.inspectedWindow.tabId;
  final json = jsonEncode(serializers.serialize(DebugStateChange((b) => b
    ..tabId = dartAppTabId
    ..newState = DebugStateChange.startDebugging)));
  sendRuntimeMessage(
      type: MessageType.debugStateChange,
      body: json,
      sender: Script.debuggerPanel,
      recipient: Script.background);
  _maybeHandleConnectionTimeout();
}

void _maybeHandleConnectionTimeout() async {
  connecting = true;
  await Future.delayed(Duration(seconds: 10));
  if (connecting == true) {
    _handleConnectFailure(ConnectFailureReason.timeout);
  }
}

void _injectDevToolsIframe(String devToolsUrl) {
  final iframeContainer = document.getElementById(iframeContainerId);
  if (iframeContainer == null) return;
  final panelBody = document.getElementById(panelBodyId);
  final panelType = panelBody?.getAttribute(panelAttribute) ?? 'debugger';
  final iframe = document.createElement('iframe');
  iframe.setAttribute(
    'src',
    '$devToolsUrl&embed=true&page=$panelType&backgroundColor=$devToolsBackgroundColor',
  );
  _hideWarningBanner();
  _updateElementVisibility(landingPageId, visible: false);
  _updateElementVisibility(loadingSpinnerId, visible: false);
  _updateElementVisibility(launchDebugConnectionButtonId, visible: true);
  iframeContainer.append(iframe);
}

void _removeDevToolsIframe() {
  final iframeContainer = document.getElementById(iframeContainerId);
  final iframe = iframeContainer?.firstChild;
  if (iframe == null) return;
  iframe.remove();
}

void _updateElementVisibility(String elementId, {required bool visible}) {
  final element = document.getElementById(elementId);
  if (element == null) return;
  if (visible) {
    element.classes.remove(hiddenClass);
  } else {
    element.classes.add(hiddenClass);
  }
}
