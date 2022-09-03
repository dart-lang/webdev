// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debugTab;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';

final channel = BroadcastChannel(debugTabChannelName);

void main() {
  _registerListeners();
}

void _registerListeners() {
  channel.addEventListener(
    'message',
    allowInterop(_handleChannelMessageEvents),
  );
}

void _handleChannelMessageEvents(Event event) {
  final messageData =
      jsEventToMessageData(event, expectedOrigin: chrome.runtime.getURL(''));
  if (messageData == null) return;

  interceptMessage<DebugInfo>(
    message: messageData,
    expectedType: MessageType.debugInfo,
    expectedSender: Script.iframe,
    expectedRecipient: Script.debugTab,
    messageHandler: _debugInfoMessageHandler,
  );
}

void _debugInfoMessageHandler(DebugInfo message) {
  final tabId = message.tabId;
  _startDebugging(tabId);
}

void _startDebugging(int tabId) {
  final debuggee = Debuggee(tabId: tabId);
  chrome.debugger.attach(debuggee, '1.3', allowInterop(() async {
    chrome.debugger.sendCommand(
        debuggee, 'Runtime.enable', EmptyParam(), allowInterop((e) {}));
  }));
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}
