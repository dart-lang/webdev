// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';
import 'dart:js';

import 'chrome_api.dart';
import 'messaging.dart';

void main() {
  _registerListeners();

  // Inject the IFRAME into the current tab.
  _injectIframe();
}

void _registerListeners() {
  window.addEventListener(
    'message',
    allowInterop(_handleWindowMessageEvents),
  );
}

void _injectIframe() {
  final iframe = document.createElement('iframe');
  final iframeSrc = chrome.runtime.getURL('iframe.html');
  iframe.setAttribute('src', iframeSrc);
  document.body?.append(iframe);
}

void _handleWindowMessageEvents(Event event) {
  final messageData =
      jsEventToMessageData(event, expectedOrigin: chrome.runtime.getURL(''));
  if (messageData == null) return;

  interceptMessage<IframeReady>(
    message: messageData,
    expectedType: MessageType.iframeReady,
    expectedSender: Script.iframe,
    expectedRecipient: Script.iframeInjector,
    messageHandler: _iframeReadyMessageHandler,
  );
}

void _iframeReadyMessageHandler(IframeReady message) {
  if (message.isReady != true) return;
  // TODO(elliette): Inject a script to fetch debug info global variables.

  // Send a message back to IFRAME so that it has access to the tab ID.
  _sendMessageToIframe(
      type: MessageType.debugState,
      encodedBody: DebugState(shouldDebug: true).toJSON());
}

void _sendMessageToIframe({
  required MessageType type,
  required String encodedBody,
}) {
  final message = Message(
    to: Script.iframe,
    from: Script.iframeInjector,
    type: type,
    encodedBody: encodedBody,
  );
  chrome.runtime.sendMessage(
    /*id*/ null,
    message.toJSON(),
    /*options*/ null,
    /*callback*/ null,
  );
}
