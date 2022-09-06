// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library iframe;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';

final _channel = BroadcastChannel(debugTabChannelName);

void main() {
  _registerListeners();

  // Send a message to the injector script that the IFRAME has loaded.
  _sendMessageToIframeInjector(
    type: MessageType.iframeReady,
    encodedBody: IframeReady(isReady: true).toJSON(),
  );
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(allowInterop(_handleRuntimeMessages));
}

void _sendMessageToIframeInjector({
  required MessageType type,
  required String encodedBody,
}) {
  final message = Message(
    to: Script.iframeInjector,
    from: Script.iframe,
    type: type,
    encodedBody: encodedBody,
  );
  window.parent?.postMessage(message.toJSON(), '*');
}

void _handleRuntimeMessages(
    dynamic jsRequest, MessageSender sender, Function sendResponse) {
  if (jsRequest is! String) return;

  interceptMessage<DebugState>(
      message: jsRequest,
      expectedType: MessageType.debugState,
      expectedSender: Script.iframeInjector,
      expectedRecipient: Script.iframe,
      messageHandler: (DebugState message) {
        final tabId = sender.tab?.id;
        if (tabId == null) return;

        _sendMessageToDebugTab(
          type: MessageType.debugInfo,
          encodedBody: DebugInfo(tabId: tabId).toJSON(),
        );
      });
}

void _sendMessageToDebugTab({
  required MessageType type,
  required String encodedBody,
}) {
  final message = Message(
    to: Script.debugTab,
    from: Script.iframe,
    type: type,
    encodedBody: encodedBody,
  );
  _channel.postMessage(message.toJSON());
}
