// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library panel;

import 'dart:async';
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

const _noAppDetectedMsg = 'No app detected.';
const _lostConnectionMsg = 'Lost connection.';
const _connectionTimeoutMsg = 'Connection timed out.';
const _failedToConnectMsg = 'Failed to connect, please try again.';
const _pleaseAuthenticateMsg = 'Please re-authenticate and try again.';
const _multipleAppsMsg = 'Cannot debug multiple apps in a page.';

int get _tabId => chrome.devtools.inspectedWindow.tabId;

Future<void> main() async {
  unawaited(
    _registerListeners().catchError((error) {
      debugWarn('Error registering listeners in panel: $error');
    }),
  );
  _setColorThemeToMatchChromeDevTools();
  await _maybeUpdateFileABugLink();
  final multipleApps = await fetchStorageObject<String>(
    type: StorageObject.multipleAppsDetected,
    tabId: _tabId,
  );
  _maybeShowMultipleAppsWarning(multipleApps);
}

Future<void> _registerListeners() async {
  chrome.storage.onChanged.addListener(allowInterop(_handleStorageChanges));
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
  final launchDebugConnectionButton =
      document.getElementById(_launchDebugConnectionButtonId) as ButtonElement;
  launchDebugConnectionButton.addEventListener('click', _launchDebugConnection);

  await _maybeInjectDevToolsIframe();
}

void _handleRuntimeMessages(
  dynamic jsRequest,
  // ignore: avoid-unused-parameters
  MessageSender sender,
  // ignore: avoid-unused-parameters
  Function sendResponse,
) {
  if (jsRequest is! String) return;

  interceptMessage<DebugStateChange>(
    message: jsRequest,
    expectedType: MessageType.debugStateChange,
    expectedSender: Script.background,
    expectedRecipient: Script.debuggerPanel,
    sender: sender,
    messageHandler: (DebugStateChange debugStateChange) async {
      if (debugStateChange.tabId != _tabId) {
        debugWarn(
          'Received debug state change request, but Dart app tab does not match current tab.',
        );
        return;
      }
      if (debugStateChange.newState == DebugStateChange.stopDebugging) {
        _handleDebugConnectionLost(debugStateChange.reason);
      }
    },
  );

  interceptMessage<ConnectFailure>(
    message: jsRequest,
    expectedType: MessageType.connectFailure,
    expectedSender: Script.background,
    expectedRecipient: Script.debuggerPanel,
    sender: sender,
    messageHandler: (ConnectFailure connectFailure) async {
      debugLog(
        'Received connect failure for ${connectFailure.tabId} vs $_tabId',
      );
      if (connectFailure.tabId != _tabId) {
        return;
      }
      _connecting = false;
      _handleConnectFailure(
        ConnectFailureReason.fromString(connectFailure.reason ?? 'unknown'),
      );
    },
  );
}

void _handleStorageChanges(Object storageObj, String _) {
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
  interceptStorageChange<String>(
    storageObj: storageObj,
    expectedType: StorageObject.multipleAppsDetected,
    tabId: _tabId,
    changeHandler: _maybeShowMultipleAppsWarning,
  );
}

void _handleDebugInfoChanges(DebugInfo? debugInfo) {
  if (debugInfo == null && _isDartApp) {
    _isDartApp = false;
    if (!_warningBannerIsVisible()) {
      _showWarningBanner(_noAppDetectedMsg);
    }
  }
  if (debugInfo != null && !_isDartApp) {
    _isDartApp = true;
    if (_warningBannerIsVisible()) {
      _hideWarningBanner();
    }
  }
}

void _handleDevToolsUriChanges(String? devToolsUri) {
  if (devToolsUri != null) {
    _injectDevToolsIframe(devToolsUri);
  }
}

void _maybeShowMultipleAppsWarning(String? multipleApps) {
  if (multipleApps != null) {
    _showWarningBanner(_multipleAppsMsg);
  } else {
    if (_warningBannerIsVisible(message: _multipleAppsMsg)) {
      _hideWarningBanner();
    }
  }
}

Future<void> _maybeUpdateFileABugLink() async {
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: _tabId,
  );
  final isInternal = debugInfo?.isInternalBuild ?? false;
  if (isInternal) {
    final bugLink = document.getElementById(_bugLinkId);
    if (bugLink == null) return;
    bugLink.setAttribute(
      'href',
      'http://go/dde-bug',
    );
  }
}

void _setColorThemeToMatchChromeDevTools() {
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
      _showWarningBanner(_noAppDetectedMsg);
      break;
    default:
      _showWarningBanner(_lostConnectionMsg);
      break;
  }
}

void _handleConnectFailure(ConnectFailureReason reason) {
  switch (reason) {
    case ConnectFailureReason.authentication:
      _showWarningBanner(_pleaseAuthenticateMsg);
      break;
    case ConnectFailureReason.noDartApp:
      _showWarningBanner(_noAppDetectedMsg);
      break;
    case ConnectFailureReason.timeout:
      _showWarningBanner(_connectionTimeoutMsg);
      break;
    default:
      _showWarningBanner(_failedToConnectMsg);
  }
  _updateElementVisibility(_launchDebugConnectionButtonId, visible: true);
  _updateElementVisibility(_loadingSpinnerId, visible: false);
}

bool _warningBannerIsVisible({String? message}) {
  final warningBanner = document.getElementById(_warningBannerId);
  final isVisible =
      warningBanner != null && warningBanner.classes.contains(_showClass);
  if (message == null || !isVisible) return isVisible;
  final warningMsg = document.getElementById(_warningMsgId);
  return warningMsg?.innerHtml == message;
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

Future<void> _launchDebugConnection(Event _) async {
  _updateElementVisibility(_launchDebugConnectionButtonId, visible: false);
  _updateElementVisibility(_loadingSpinnerId, visible: true);
  final json = jsonEncode(
    serializers.serialize(
      DebugStateChange(
        (b) => b
          ..tabId = _tabId
          ..newState = DebugStateChange.startDebugging,
      ),
    ),
  );
  await sendRuntimeMessage(
    type: MessageType.debugStateChange,
    body: json,
    sender: Script.debuggerPanel,
    recipient: Script.background,
  );
  unawaited(_maybeHandleConnectionTimeout().catchError((_) {}));
}

Future<void> _maybeHandleConnectionTimeout() async {
  _connecting = true;
  await Future.delayed(Duration(seconds: 10));
  if (_connecting) {
    _handleConnectFailure(ConnectFailureReason.timeout);
  }
}

Future<void> _maybeInjectDevToolsIframe() async {
  final devToolsUri = await fetchStorageObject<String>(
    type: StorageObject.devToolsUri,
    tabId: _tabId,
  );
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
      'backgroundColor': _backgroundColor,
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
