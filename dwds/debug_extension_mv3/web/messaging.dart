// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library messaging;

import 'dart:convert';
import 'dart:html';

import 'package:js/js.dart';

import 'web_api.dart';

const debugTabChannelName = 'DEBUG_TAB_CHANNEL';

enum Script {
  background,
  debugTab,
  iframe,
  iframeInjector;

  factory Script.fromString(String value) {
    return Script.values.byName(value);
  }
}

enum MessageType {
  debugInfo,
  debugState,
  iframeReady;

  factory MessageType.fromString(String value) {
    return MessageType.values.byName(value);
  }
}

class Message {
  final Script to;
  final Script from;
  final MessageType type;
  final String encodedBody;
  final String? error;

  Message({
    required this.to,
    required this.from,
    required this.type,
    required this.encodedBody,
    this.error,
  });

  factory Message.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    return Message(
      to: Script.fromString(decoded['to'] as String),
      from: Script.fromString(decoded['from'] as String),
      type: MessageType.fromString(decoded['type'] as String),
      encodedBody: decoded['encodedBody'] as String,
      error: decoded['error'] as String?,
    );
  }

  String toJSON() {
    return jsonEncode({
      'type': type.name,
      'to': to.name,
      'from': from.name,
      'encodedBody': encodedBody,
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
  try {
    if (message == null) return;
    final decodedMessage = Message.fromJSON(message);
    if (decodedMessage.type != expectedType ||
        decodedMessage.to != expectedRecipient ||
        decodedMessage.from != expectedSender) {
      return;
    }
    final messageType = decodedMessage.type;
    final messageBody = decodedMessage.encodedBody;
    switch (messageType) {
      case MessageType.debugInfo:
        messageHandler(DebugInfo.fromJSON(messageBody) as T);
        break;
      case MessageType.debugState:
        messageHandler(DebugState.fromJSON(messageBody) as T);
        break;
      case MessageType.iframeReady:
        messageHandler(IframeReady.fromJSON(messageBody) as T);
        break;
    }
  } catch (error) {
    console.warn('Error intercepting expected message: $error');
    return;
  }
}

String? jsEventToMessageData(
  Event event, {
  required String expectedOrigin,
}) {
  try {
    final messageEvent = event as MessageEvent;
    final origin = messageEvent.origin;
    if (origin.removeTrailingSlash() != expectedOrigin.removeTrailingSlash()) {
      return null;
    }
    return messageEvent.data as String;
  } catch (error) {
    console.warn('Error converting event to message data: $error');
    return null;
  }
}

class IframeReady {
  final bool isReady;

  IframeReady({required this.isReady});

  factory IframeReady.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final isReady = decoded['isReady'] as bool;
    return IframeReady(isReady: isReady);
  }

  String toJSON() {
    return jsonEncode({
      'isReady': isReady,
    });
  }
}

class DebugState {
  final bool shouldDebug;

  DebugState({required this.shouldDebug});

  factory DebugState.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final shouldDebug = decoded['shouldDebug'] as bool;
    return DebugState(shouldDebug: shouldDebug);
  }

  String toJSON() {
    return jsonEncode({
      'shouldDebug': shouldDebug,
    });
  }
}

class DebugInfo {
  final int tabId;

  DebugInfo({required this.tabId});

  factory DebugInfo.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final tabId = decoded['tabId'] as int;
    return DebugInfo(tabId: tabId);
  }

  String toJSON() {
    return jsonEncode({
      'tabId': tabId,
    });
  }
}

extension RemoveTrailingSlash on String {
  String removeTrailingSlash() {
    final trailingSlash = '/';
    if (this.endsWith(trailingSlash)) {
      return this.substring(0, length - 1);
    }
    return this;
  }
}
