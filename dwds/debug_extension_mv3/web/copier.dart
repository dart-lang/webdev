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
  // ignore: avoid-unused-parameters
  Function sendResponse,
) {
  interceptMessage<String>(
    message: jsRequest,
    expectedType: MessageType.appId,
    expectedSender: Script.background,
    expectedRecipient: Script.copier,
    messageHandler: _copyAppId,
  );
}

void _copyAppId(String appId) {
  final clipboard = window.navigator.clipboard;
  if (clipboard == null) return;
  clipboard.writeText(appId);
  _showCopiedMessage(appId);
}

Future<void> _showCopiedMessage(String appId) async {
  final snackbar = document.createElement('div');
  snackbar.setInnerHtml('Copied $appId!');
  snackbar.classes.add('snackbar snackbar--info show');
  document.body?.append(snackbar);
  await Future.delayed(Duration(seconds: 2));
  snackbar.remove();
}
