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
  _registerListeners();

// Send message to the injector script that the IFRAME has loaded.
// This allows the injector script to send a message back, so
// that the IFRAME has access to its tab ID.
  console.log('letting injector know that iframe is ready');
  _sendMessageToIframeInjector<IframeReady>(IframeReady(isReady: true));
}

void _sendMessageToIframeInjector<T>(T messageBody) {
  window.parent?.postMessage(
      buildMessage<T>(
        to: Script.iframeInjector,
        from: Script.iframe,
        body: messageBody,
      ),
      '*');
}

void _registerListeners() {
  chrome.runtime.onMessage
      .addListener(allowInterop(_handleMessageFromIframeInjector));
}

void _handleMessageFromIframeInjector(
    dynamic jsRequest, MessageSender sender, Function sendResponse) {
  if (jsRequest == null) return;
  final tabId = sender.tab?.id;
  if (tabId == null) return;

  console.log('received a message from iframe injector! $jsRequest');

  handleExpectedMessage<DebuggingState>(
      interceptedMessage: jsRequest,
      expectedSender: Script.iframeInjector,
      expectedRecipient: Script.iframe,
      messageHandler: (DebuggingState message) {
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
