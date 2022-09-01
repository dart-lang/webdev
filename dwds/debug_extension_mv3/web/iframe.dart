// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library iframe;

import 'dart:html';

import 'chrome_api.dart';
import 'messaging.dart';
import 'web_api.dart';

import 'package:js/js.dart';

void main() {
  console.log('iframe injected!!');
  _listenForMessagesFromIframeInjector();

// Send message to the injector script that the IFRAME has loaded.
// This allows the injector script to send a message back, so
// that the IFRAME has access to its tab ID.
  final iframeReadyMessage = Message<IframeReady>(
    sender: Script.iframe,
    recipient: Script.iframeInjector,
    body: IframeReady(isReady: true),
  );
  _sendMessageToIframeInjector<IframeReady>(iframeReadyMessage);
}

void _sendMessageToIframeInjector<T>(Message<T> message) {
  window.parent?.postMessage(message, '*');
}

void _listenForMessagesFromIframeInjector() {
  chrome.runtime.onMessage
      .addListener(allowInterop(_handleMessageFromIframeInjector));
}

void _handleMessageFromIframeInjector(
    dynamic jsRequest, MessageSender sender, Function sendResponse) {
  if (jsRequest == null) return;
  final tabId = sender.tab?.id;
  if (tabId == null) return;

  handleExpectedMessage<DebuggingState>(
      interceptedMessage: jsRequest,
      expectedSender: Script.iframeInjector,
      expectedRecipient: Script.iframe,
      messageHandler: (Message<DebuggingState> message) {
        final debuggee = Debuggee(tabId: tabId);
        chrome.debugger.attach(debuggee, '1.3', allowInterop(() async {
          chrome.debugger.sendCommand(
              debuggee, 'Runtime.enable', EmptyParam(), allowInterop((e) {}));
        }));
      });
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}
