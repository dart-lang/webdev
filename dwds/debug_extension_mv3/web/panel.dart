// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library panel;

import 'dart:convert';
import 'dart:html';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_serializers.dart';
import 'data_types.dart';
import 'debug_session.dart';
import 'logger.dart';
import 'messaging.dart';
import 'storage.dart';
import 'utils.dart';

bool _connecting = false;
String _backgroundColor = _darkColor;
bool _isDartApp = true;

const _bugLinkId = 'bugLink';
const _darkColor = '202125';
const _darkThemeClass = 'dark-theme';
const _hiddenClass = 'hidden';
const _iframeContainerId = 'iframeContainer';
const _landingPageId = 'landingPage';
const _launchDebugConnectionButtonId = 'launchDebugConnectionButton';
const _lightColor = 'ffffff';
const _lightThemeClass = 'light-theme';
const _loadingSpinnerId = 'loadingSpinner';
const _panelAttribute = 'data-panel';
const _panelBodyId = 'panelBody';
const _showClass = 'show';
const _warningBannerId = 'warningBanner';
const _warningMsgId = 'warningMsg';

int get _tabId => chrome.devtools.inspectedWindow.tabId;

void main() {
  _registerListeners();
  _setColorThemeToMatchChromeDevTools();
  _maybeUpdateFileABugLink();
}

void _registerListeners() {
  chrome.storage.onChanged.addListener(allowInterop(_handleStorageChanges));
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
  final launchDebugConnectionButton =
      document.getElementById(_launchDebugConnectionButtonId) as ButtonElement;
  launchDebugConnectionButton.addEventListener('click', _launchDebugConnection);

  _maybeInjectDevToolsIframe();
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest is! String) return;

  interceptMessage<DebugStateChange>(
      message: jsRequest,
      expectedType: MessageType.debugStateChange,
      expectedSender: Script.background,
      expectedRecipient: Script.debuggerPanel,
      messageHandler: (DebugStateChange debugStateChange) async {
        if (debugStateChange.tabId != _tabId) {
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
            'Received connect failure for ${connectFailure.tabId} vs $_tabId');
        if (connectFailure.tabId != _tabId) {
          return;
        }
        _connecting = false;
        _handleConnectFailure(
          ConnectFailureReason.fromString(connectFailure.reason ?? 'unknown'),
        );
      });
}

void _handleStorageChanges(Object storageObj, String storageArea) {
  interceptStorageChange<DebugInfo>(
    storageObj: storageObj,
    expectedType: StorageObject.debugInfo,
    tabId: _tabId,
    changeHandler: _handleDebugInfoChanges,
  );
  interceptStorageChange<String>(
    storageObj: storageObj,
    expectedType: StorageObject.devToolsUri,
    tabId: _tabId,
    changeHandler: _handleDevToolsUriChanges,
  );
}

void _handleDebugInfoChanges(DebugInfo? debugInfo) async {
  if (debugInfo == null && _isDartApp) {
    _isDartApp = false;
    if (!_warningBannerIsVisible()) {
      _showWarningBanner('No app detected.');
    }
  }
  if (debugInfo != null && !_isDartApp) {
    _isDartApp = true;
    if (_warningBannerIsVisible()) {
      _hideWarningBanner();
    }
  }
}

void _handleDevToolsUriChanges(String? devToolsUri) async {
  if (devToolsUri != null) {
    _injectDevToolsIframe(devToolsUri);
  }
}

void _maybeUpdateFileABugLink() async {
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: _tabId,
  );
  final isInternal = debugInfo?.isInternalBuild ?? false;
  if (isInternal) {
    final bugLink = document.getElementById(_bugLinkId);
    if (bugLink == null) return;
    bugLink.setAttribute(
        'href', 'http://b/issues/new?component=775375&template=1369639');
  }
}

void _setColorThemeToMatchChromeDevTools() async {
  final chromeTheme = chrome.devtools.panels.themeName;
  final panelBody = document.getElementById(_panelBodyId);
  if (chromeTheme == 'dark') {
    _backgroundColor = _darkColor;
    _updateColorThemeForElement(panelBody, isDarkTheme: true);
  } else {
    _backgroundColor = _lightColor;
    _updateColorThemeForElement(panelBody, isDarkTheme: false);
  }
}

void _updateColorThemeForElement(
  Element? element, {
  required bool isDarkTheme,
}) {
  if (element == null) return;
  final classToRemove = isDarkTheme ? _lightThemeClass : _darkThemeClass;
  if (element.classes.contains(classToRemove)) {
    element.classes.remove(classToRemove);
    final classToAdd = isDarkTheme ? _darkThemeClass : _lightThemeClass;
    element.classes.add(classToAdd);
  }
}

void _handleDebugConnectionLost(String? reason) {
  final detachReason = DetachReason.fromString(reason ?? 'unknown');
  _removeDevToolsIframe();
  _updateElementVisibility(_landingPageId, visible: true);
  switch (detachReason) {
    case DetachReason.canceledByUser:
      return;
    case DetachReason.staleDebugSession:
    case DetachReason.navigatedAwayFromApp:
      _showWarningBanner('No app detected.');
      break;
    default:
      _showWarningBanner('Lost connection.');
      break;
  }
}

void _handleConnectFailure(ConnectFailureReason reason) {
  switch (reason) {
    case ConnectFailureReason.authentication:
      _showWarningBanner('Please re-authenticate and try again.');
      break;
    case ConnectFailureReason.noDartApp:
      _showWarningBanner('No app detected.');
      break;
    case ConnectFailureReason.timeout:
      _showWarningBanner('Connection timed out.');
      break;
    default:
      _showWarningBanner('Failed to connect, please try again.');
  }
  _updateElementVisibility(_launchDebugConnectionButtonId, visible: true);
  _updateElementVisibility(_loadingSpinnerId, visible: false);
}

bool _warningBannerIsVisible() {
  final warningBanner = document.getElementById(_warningBannerId);
  return warningBanner != null && warningBanner.classes.contains(_showClass);
}

void _showWarningBanner(String message) {
  final warningMsg = document.getElementById(_warningMsgId);
  warningMsg?.setInnerHtml(message);
  final warningBanner = document.getElementById(_warningBannerId);
  warningBanner?.classes.add(_showClass);
}

void _hideWarningBanner() {
  final warningBanner = document.getElementById(_warningBannerId);
  warningBanner?.classes.remove(_showClass);
}

void _launchDebugConnection(Event _) async {
  _updateElementVisibility(_launchDebugConnectionButtonId, visible: false);
  _updateElementVisibility(_loadingSpinnerId, visible: true);
  final json = jsonEncode(serializers.serialize(DebugStateChange((b) => b
    ..tabId = _tabId
    ..newState = DebugStateChange.startDebugging)));
  await sendRuntimeMessage(
      type: MessageType.debugStateChange,
      body: json,
      sender: Script.debuggerPanel,
      recipient: Script.background);
  _maybeHandleConnectionTimeout();
}

void _maybeHandleConnectionTimeout() async {
  _connecting = true;
  await Future.delayed(Duration(seconds: 10));
  if (_connecting == true) {
    _handleConnectFailure(ConnectFailureReason.timeout);
  }
}

void _maybeInjectDevToolsIframe() async {
  final devToolsUri = await fetchStorageObject<String>(
      type: StorageObject.devToolsUri, tabId: _tabId);
  if (devToolsUri == null) return;
  if (isActiveDebugSession(_tabId)) {
    debugWarn('Unexpected state. Stale DevTools URI.');
    await clearStaleDebugSession(_tabId);
    _updateElementVisibility(_landingPageId, visible: true);
  } else {
    _injectDevToolsIframe(devToolsUri);
  }
}

void _injectDevToolsIframe(String devToolsUri) {
  _connecting = false;
  final iframeContainer = document.getElementById(_iframeContainerId);
  if (iframeContainer == null) return;
  final panelBody = document.getElementById(_panelBodyId);
  final panelType = panelBody?.getAttribute(_panelAttribute) ?? 'debugger';
  final iframe = document.createElement('iframe');
  final iframeSrc = addQueryParameters(
    devToolsUri,
    queryParameters: {
      'ide': 'ChromeDevTools',
      'embed': 'true',
      'page': panelType,
      '_backgroundColor': _backgroundColor,
    },
  );
  iframe.setAttribute('src', iframeSrc);
  _hideWarningBanner();
  _updateElementVisibility(_landingPageId, visible: false);
  _updateElementVisibility(_loadingSpinnerId, visible: false);
  _updateElementVisibility(_launchDebugConnectionButtonId, visible: true);
  iframeContainer.append(iframe);
}

void _removeDevToolsIframe() {
  final iframeContainer = document.getElementById(_iframeContainerId);
  final iframe = iframeContainer?.firstChild;
  if (iframe == null) return;
  iframe.remove();
}

void _updateElementVisibility(String elementId, {required bool visible}) {
  final element = document.getElementById(elementId);
  if (element == null) return;
  if (visible) {
    element.classes.remove(_hiddenClass);
  } else {
    element.classes.add(_hiddenClass);
  }
}
