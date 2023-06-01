// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library messaging;

import 'dart:async';
import 'dart:convert';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_serializers.dart';
import 'logger.dart';

enum Script {
  background,
  debuggerPanel,
  detector;

  factory Script.fromString(String value) {
    return Script.values.byName(value);
  }
}

enum MessageType {
  isAuthenticated,
  connectFailure,
  debugInfo,
  debugStateChange,
  devToolsUrl,
  multipleAppsDetected;

  factory MessageType.fromString(String value) {
    return MessageType.values.byName(value);
  }
}

class Message {
  final Script to;
  final Script from;
  final MessageType type;
  final String body;
  final String? error;

  Message({
    required this.to,
    required this.from,
    required this.type,
    required this.body,
    this.error,
  });

  factory Message.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    return Message(
      to: Script.fromString(decoded['to'] as String),
      from: Script.fromString(decoded['from'] as String),
      type: MessageType.fromString(decoded['type'] as String),
      body: decoded['body'] as String,
      error: decoded['error'] as String?,
    );
  }

  String toJSON() {
    return jsonEncode({
      'to': to.name,
      'from': from.name,
      'type': type.name,
      'body': body,
      if (error != null) 'error': error,
    });
  }
}

void interceptMessage<T>({
  required String? message,
  required MessageType expectedType,
  required Script expectedSender,
  required Script expectedRecipient,
  required void Function(T message) messageHandler,
}) {
  if (message == null) return;
  try {
    final decodedMessage = Message.fromJSON(message);
    if (decodedMessage.type != expectedType ||
        decodedMessage.to != expectedRecipient ||
        decodedMessage.from != expectedSender) {
      return;
    }
    if (T == String) {
      messageHandler(decodedMessage.body as T);
    } else {
      messageHandler(
        serializers.deserialize(jsonDecode(decodedMessage.body)) as T,
      );
    }
  } catch (error) {
    debugError(
      'Error intercepting $expectedType from $expectedSender to $expectedRecipient: $error',
    );
  }
}

Future<bool> sendRuntimeMessage({
  required MessageType type,
  required String body,
  required Script sender,
  required Script recipient,
}) {
  final message = Message(
    to: recipient,
    from: sender,
    type: type,
    body: body,
  );
  final completer = Completer<bool>();
  chrome.runtime.sendMessage(
    // id
    null,
    message.toJSON(),
    // options
    null,
    allowInterop(() {
      final error = chrome.runtime.lastError;
      if (error != null) {
        debugError(
          'Error sending $type to $recipient from $sender: ${error.message}',
        );
      }
      completer.complete(error != null);
    }),
  );
  return completer.future;
}
