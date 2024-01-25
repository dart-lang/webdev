// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library messaging;

import 'dart:async';
import 'dart:convert';
import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_serializers.dart';
import 'logger.dart';
import 'utils.dart';

// A default response for the sendResponse callback.
//
// Prevents the message port from closing. See:
// https://developer.chrome.com/docs/extensions/mv3/messaging/#simple
final defaultResponse = jsify({'response': 'received'});

enum Script {
  background,
  copier,
  debuggerPanel,
  detector,
  popup;

  factory Script.fromString(String value) {
    return Script.values.byName(value);
  }
}

enum MessageType {
  isAuthenticated,
  connectFailure,
  appId,
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
  required MessageSender sender,
  required void Function(T message) messageHandler,
}) {
  if (message == null) return;
  if (!_isLegitimateSender(sender)) return;

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

/// Send a message using the chrome.runtime.sendMessage API.
Future<bool> sendRuntimeMessage({
  required MessageType type,
  required String body,
  required Script sender,
  required Script recipient,
}) =>
    _sendMessage(
      type: type,
      body: body,
      sender: sender,
      recipient: recipient,
    );

/// Send a message using the chrome.tabs.sendMessage API.
Future<bool> sendTabsMessage({
  required int tabId,
  required MessageType type,
  required String body,
  required Script sender,
  required Script recipient,
}) =>
    _sendMessage(
      tabId: tabId,
      type: type,
      body: body,
      sender: sender,
      recipient: recipient,
    );

Future<bool> _sendMessage({
  required MessageType type,
  required String body,
  required Script sender,
  required Script recipient,
  int? tabId,
}) {
  final message = Message(
    to: recipient,
    from: sender,
    type: type,
    body: body,
  ).toJSON();
  final completer = Completer<bool>();
  void responseHandler([dynamic _]) {
    final error = chrome.runtime.lastError;
    if (error != null) {
      debugError(
        'Error sending $type to $recipient from $sender: ${error.message}',
      );
    }
    completer.complete(error != null);
  }

  if (tabId != null) {
    chrome.tabs.sendMessage(
      tabId,
      message,
      // options
      null,
      allowInterop(responseHandler),
    );
  } else {
    chrome.runtime.sendMessage(
      // id
      null,
      message,
      // options
      null,
      allowInterop(responseHandler),
    );
  }
  return completer.future;
}

// Verify the message sender is our extension.
bool _isLegitimateSender(MessageSender sender) {
  // Check that the sender ID matches our extension ID:
  if (sender.id != chrome.runtime.id) return false;

  final senderUri = Uri.parse(sender.origin ?? '');
  final senderHost = senderUri.host;
  final isDartAppHost = senderHost == 'localhost' ||
      senderHost == '127.0.0.1' ||
      _isGoogleHost(senderHost);
  final isExtensionOrigin =
      senderHost == chrome.runtime.id && senderUri.scheme == 'chrome-extension';

  if (isDartAppHost || isExtensionOrigin) return true;

  // If the sender's host is unexpected, display an error.
  displayNotification(
    'Unexpected sender ${sender.origin}. Please file a bug at go/dde-bug or https://github.com/dart-lang/webdev',
    isError: true,
  );
  return false;
}

bool _isGoogleHost(String host) {
  const googleSuffices = ['.googlers.com', '.google.com', '.googleprod.com'];
  return googleSuffices.any((suffix) => host.endsWith(suffix));
}
