// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library copier;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  chrome.runtime.onMessage.addListener(
    allowInterop(_handleRuntimeMessages),
  );
}

void _handleRuntimeMessages(
  dynamic jsRequest,
  MessageSender sender,
  Function sendResponse,
) {
  interceptMessage<String>(
    message: jsRequest,
    expectedType: MessageType.appId,
    expectedSender: Script.background,
    expectedRecipient: Script.copier,
    sender: sender,
    messageHandler: _copyAppId,
  );

  sendResponse(defaultResponse);
}

void _copyAppId(String appId) {
  final clipboard = window.navigator.clipboard;
  if (clipboard == null) return;
  clipboard.writeText(appId);
  _notifyCopiedSuccess(appId);
}

Future<bool> _notifyCopiedSuccess(String appId) => sendRuntimeMessage(
      type: MessageType.appId,
      body: appId,
      sender: Script.copier,
      recipient: Script.background,
    );
