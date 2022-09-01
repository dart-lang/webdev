// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library messaging;

import 'dart:html';
import 'package:js/js.dart';

enum Script {
  background,
  iframe,
  iframeInjector,
}

@JS()
@anonymous
class Message<T> {
  external Script get sender;
  external Script get recipient;
  external T get body;
  external String? get error;

  external factory Message({
    required Script sender,
    required Script recipient,
    required T body,
    String? error = null,
  });
}

void handleExpectedMessage<T>({
  required Object? interceptedMessage,
  required Script expectedSender,
  required Script expectedRecipient,
  required void Function(Message<T> message) messageHandler,
}) {
  try {
    final message = interceptedMessage as Message<T>;
    if (message.sender != expectedSender &&
        message.recipient != expectedRecipient) {
      return;
    }
    messageHandler(message);
  } catch (_) {
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
