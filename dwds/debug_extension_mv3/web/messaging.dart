// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library messaging;

import 'dart:html';
import 'dart:js';
import 'package:js/js.dart';
import 'web_api.dart';

enum Script { background, iframe, iframeInjector }

Message<T> buildMessage<T>({
  required Script to,
  required Script from,
  required T body,
  String? error,
}) {
  return Message<T>(
    recipient: to.toString(),
    sender: from.toString(),
    body: body,
    error: error,
  );
}

void handleExpectedMessage<T>({
  required Object? interceptedMessage,
  required Script expectedSender,
  required Script expectedRecipient,
  required void Function(T message) messageHandler,
}) {
  try {
    if (interceptedMessage == null) return;
    final message = Map<String, dynamic>.from(interceptedMessage as Map<dynamic, dynamic>);
    if (message['sender'] != expectedSender.toString() &&
        message['recipient'] != expectedRecipient.toString()) {
      window.console.log('returning, unexpected sender / recipient');
      return;
    }
    final messageBody = message['body'] as T;
    messageHandler(messageBody);
  } catch (_) {
    console.log('ERROR CONVERTING MESSAGe $_');
    return;
  }
}

MessageEvent? jsEventToMessageEvent<T>(Event event) {
  try {
    final messageEvent = event as MessageEvent;
    return messageEvent;
  } catch (_) {
    return null;
  }
}

@JS()
@anonymous
class Message<T> {
  external String get sender;
  external String get recipient;
  external T get body;
  external String? get error;

  external factory Message({
    required String sender,
    required String recipient,
    required T body,
    String? error = null,
  });
}

@JS()
@anonymous
class IframeReady {
  external bool get isReady;
  external factory IframeReady({
    required bool isReady,
  });
}

@JS()
@anonymous
class DebuggingState {
  external bool get shouldDebug;
  external factory DebuggingState({
    required bool shouldDebug,
  });
}
