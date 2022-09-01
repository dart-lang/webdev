// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';
import 'dart:js';

import 'chrome_api.dart';
import 'messaging.dart';

void main() {
  window.console.log('INJECTING IFRAME!!!');
  _listenForMessagesFromIframe();
  _injectIframe();
}

void _listenForMessagesFromIframe() {
  window.addEventListener(
    'message',
    allowInterop(_handleMessageFromIframe),
  );
}

void _handleMessageFromIframe(Event event) {
  final messageEvent = jsEventToMessageEvent(event);
  if (messageEvent == null) return;

  handleExpectedMessage<IframeReady>(
    interceptedMessage: messageEvent.data,
    expectedSender: Script.iframe,
    expectedRecipient: Script.iframeInjector,
    messageHandler: _handleIframeReadyMessage,
  );
}

void _handleIframeReadyMessage(Message<IframeReady> message) {
    if (message.body.isReady == true) {
    final startDebuggingMessage = Message<DebuggingState>(
      sender: Script.iframeInjector,
      recipient: Script.iframe,
      body: DebuggingState(shouldDebug: true),
    );
    _sendMessageToIframe<DebuggingState>(startDebuggingMessage);
  }
}

void _injectIframe() {
  final iframe = document.createElement('iframe');
  final iframeSrc = chrome.runtime.getURL('iframe.html');
  iframe.setAttribute('src', iframeSrc);
  document.body?.append(iframe);
}

void _sendMessageToIframe<T>(Message<T> message) {
  chrome.runtime.sendMessage(null, message, null, null);
}
