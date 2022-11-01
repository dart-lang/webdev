// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library detector;

import 'dart:html';
import 'package:js/js.dart';
import 'dart:js_util';

import 'chrome_api.dart';
import 'messaging.dart';
import 'web_api.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  document.addEventListener('dart-app-ready', _onDartAppReadyEvent);
}

void _onDartAppReadyEvent(Event event) {
  final debugInfo = getProperty(event, 'detail') as String?;
  if (debugInfo == null) {
    console.warn('Can\'t debug Dart app without debug info.');
    return;
  }
  _sendMessageToBackgroundScript(
    type: MessageType.debugInfo,
    body: debugInfo,
  );
}

void _sendMessageToBackgroundScript({
  required MessageType type,
  required String body,
}) {
  final message = Message(
    to: Script.background,
    from: Script.detector,
    type: type,
    body: body,
  );
  chrome.runtime.sendMessage(
    /*id*/ null,
    message.toJSON(),
    /*options*/ null,
    /*callback*/ null,
  );
}