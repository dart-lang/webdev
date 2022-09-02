// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';
import 'dart:js';

import 'chrome_api.dart';
import 'messaging.dart';

void main() {
  _registerListeners();
  _injectIframe();
}

void _registerListeners() {
  // Register a listener for window events:
  window.addEventListener(
    'message',
    allowInterop((event) {
      window.console.log('received event: ${event}');
      final messageEvent = jsEventToMessageEvent(event);
      window.console.log('received message from iframe: ${messageEvent}');
      if (messageEvent == null) return;
      _handleMessageFromIframe(messageEvent.data);
    }),
  );
}

void _injectIframe() {
  final iframe = document.createElement('iframe');
  final iframeSrc = chrome.runtime.getURL('iframe.html');
  iframe.setAttribute('src', iframeSrc);
  document.body?.append(iframe);
}

void _handleMessageFromIframe(Object? message) {
  handleExpectedMessage<IframeReady>(
    interceptedMessage: message,
    expectedSender: Script.iframe,
    expectedRecipient: Script.iframeInjector,
    messageHandler: _handleIframeReadyMessage,
  );
}

void _handleIframeReadyMessage(IframeReady message) {
  if (message.isReady == true) {
    window.console
        .log('iframe says that is is ready, telling it to start debug');
    _sendMessageToIframe<DebuggingState>(DebuggingState(shouldDebug: true));
  }
}

void _sendMessageToIframe<T>(T messageBody) {
  chrome.runtime.sendMessage(
      null,
      buildMessage<T>(
        to: Script.iframe,
        from: Script.iframeInjector,
        body: messageBody,
      ),
      null,
      null);
}
