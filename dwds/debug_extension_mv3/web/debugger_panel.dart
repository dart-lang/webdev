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

bool connecting = false;

void main() {
  _registerListeners();
  _maybeUpdateFileABugLink();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
  final launchDebuggerButton =
      document.getElementById('launchDebuggerButton') as ButtonElement;
  launchDebuggerButton.addEventListener('click', _launchDebugConnection);
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
        if (connectFailure.tabId != tabId) {
          return;
        }
        connecting = false;
        _handleConnectFailure(
          ConnectFailureReason.fromString(connectFailure.reason ?? 'unknown'),
        );
      });
}

void _maybeUpdateFileABugLink() async {
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: chrome.devtools.inspectedWindow.tabId,
  );
  final isInternal = debugInfo?.isInternalBuild ?? false;
  if (isInternal) {
    final bugLink = document.getElementById('bugLink');
    if (bugLink == null) return;
    bugLink.setAttribute('src',
        'https://b.corp.google.com/issues/new?component=775375&template=1369639');
  }
}

void _handleDebugConnectionLost(String? reason) {
  final detachReason = DetachReason.fromString(reason ?? 'unknown');
  // Remove Dart DevTools IFRAME:
  _removeDevToolsIframe();
  _updateElementVisibility('landingPage', visible: true);
  if (detachReason != DetachReason.canceled_by_user) {
    _showWarningBanner('Lost connection.');
  }
}

void _handleConnectFailure(ConnectFailureReason reason) {
  switch (reason) {
    case ConnectFailureReason.authentication:
      _showWarningBanner('Please re-authenticate and try again.');
      break;
    case ConnectFailureReason.no_dart_app:
      _showWarningBanner('No Dart app detected.');
      break;
    case ConnectFailureReason.timeout:
      _showWarningBanner('Connection timed out.');
      break;
    default:
      _showWarningBanner('Failed to connect, please try again.');
  }
  _updateElementVisibility('launchDebuggerButton', visible: true);
  _updateElementVisibility('loadingSpinner', visible: false);
}

void _showWarningBanner(String message) {
  final warningMsg = document.getElementById('warningMsg');
  warningMsg?.setInnerHtml(message);
  _updateElementVisibility('warningBanner', visible: true);
}

void _launchDebugConnection(Event _) async {
  _updateElementVisibility('launchDebuggerButton', visible: false);
  _updateElementVisibility('loadingSpinner', visible: true);
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
  final iframeContainer = document.getElementById('iframeContainer');
  if (iframeContainer == null) return;
  final iframe = document.createElement('iframe');
  iframe.setAttribute('src', '$devToolsUrl&embed=true&page=debugger');
  iframe.setAttribute('id', 'dartDebugExtensionIframe');
  _updateElementVisibility('landingPage', visible: false);
  _updateElementVisibility('lostConnectionSnackbar', visible: false);
  _updateElementVisibility('loadingSpinner', visible: false);
  _updateElementVisibility('launchDebuggerButton', visible: true);
  iframeContainer.append(iframe);
}

void _removeDevToolsIframe() {
  final iframeContainer = document.getElementById('iframeContainer');
  final iframe = iframeContainer?.firstChild;
  if (iframe == null) return;
  iframe.remove();
  _updateElementVisibility('lostConnectionSnackbar', visible: true);
}

void _updateElementVisibility(String elementId, {required bool visible}) {
  final element = document.getElementById(elementId);
  if (element == null) return;
  if (visible) {
    element.classes.remove('hidden');
  } else {
    element.classes.add('hidden');
  }
}
