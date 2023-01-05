// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library cross_extension_communication;

import 'dart:convert';

import 'package:dwds/data/serializers.dart';
import 'package:js/js.dart';

import 'debug_session.dart';
import 'logger.dart';
import 'chrome_api.dart';
import 'web_api.dart';
import 'storage.dart';
import 'debug_session.dart';

const _angularDartDevToolsId = 'nbkbficgbembimioedhceniahniffgpl';

// A map of events to the IDs of the external extensions that
// those events should be forwarded to. This is only used to forward outgoing
// messages. Incoming messages are restricted by externally_connectable in
// manifest.json.
final _eventsForExternalExtensions = {
  'Overlay.inspectNodeRequested': [_angularDartDevToolsId],
  'dwds.encodedUri': [_angularDartDevToolsId],
};

void handleMessagesFromExternalExtensions(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest == null) return;
  final message = jsRequest as ExternalExtensionMessage;
  if (message.name == 'chrome.debugger.sendCommand') {
    try {
      final options = message.options as SendCommandOptions;
      chrome.debugger.sendCommand(
          Debuggee(tabId: message.tabId),
          options.method,
          options.commandParams,
          allowInterop(([e]) {
        // No arguments indicate that an error occurred.
        if (e == null) {
          sendResponse(ErrorResponse()
            ..error = JSON.stringify(chrome.runtime.lastError));
        } else {
          sendResponse(e);
        }
      }
    ));
    } catch (e) {
      sendResponse(ErrorResponse()..error = '$e');
    }
  } else if (message.name == 'dwds.encodedUri') {
      final encodedUri = await fetchStorageObject<EncodedUri>(
      type: StorageObject.encodedUri, tabId: message.tabId);
    sendResponse(encodedUri ?? '');
  } else if (message.name == 'dwds.startDebugging') {
    attachDebugger(message.tabId);
    sendResponse(true);
  } else {
    sendResponse(
        ErrorResponse()..error = 'Unknown message name: ${message.name}');
  }
}

void maybeForwardMessageToExternalExtensions(
    {required String method, required dynamic params, required int tabId}) {
  final extensionIds = _eventsForExternalExtensions[method];
  if (extensionIds == null) return;

  final message = method.startsWith('dwds')
      ? _dwdsEventMessage(method: method, params: params, tabId: tabId)
      : _debugEventMessage(method: method, params: params, tabId: tabId);

  for (final extensionId in extensionIds) {
    _forwardMessageToExternalExtension(message, recipient: extensionId);
  }
}

void _forwardMessageToExternalExtension(
  ExternalExtensionMessage message, {
  required String recipient,
}) {
  try {
    chrome.runtime.sendMessage(
      recipient,
      message,
      /* options */ null,
      allowInterop(([e]) {
        if (e == null) {
          // Error sending message:
          final errorMessage =
              chrome.runtime.lastError?.message ?? 'Unknown error.';
          debugWarn(
              'Error forwarding ${message.name} to $recipient: $errorMessage');
        }
      }),
    );
  } catch (error) {
    debugWarn('Error forwarding ${message.name} to $recipient: $error');
  }
}

ExternalExtensionMessage _debugEventMessage({
  required String method,
  required dynamic params,
  required int tabId,
}) =>
    ExternalExtensionMessage(
      name: 'chrome.debugger.event',
      tabId: tabId,
      options: DebugEvent(method: method, params: params),
    );

ExternalExtensionMessage _dwdsEventMessage({
  required String method,
  required dynamic params,
  required int tabId,
}) =>
    ExternalExtensionMessage(
      name: method,
      tabId: tabId,
      options: params,
    );

// This message is used for cross-extension communication (eg, to send messages
// between this extension and the AngularDart DevTools extension.)
@JS()
@anonymous
class ExternalExtensionMessage {
  external int get tabId;
  external String get name;
  external dynamic get options;
  external factory ExternalExtensionMessage(
      {required int tabId, required String name, required dynamic options});
}

@JS()
@anonymous
class DebugEvent {
  external factory DebugEvent({String method, Object? params});
}

@JS()
@anonymous
class SendCommandOptions {
  external String get method;
  external Object get commandParams;
}

@JS()
@anonymous
class Request {
  external String get dartAppId;
  external String get sender;
  external int get tabId;
  external String get name;
  external dynamic get options;
  external String get warning;
  external String get message;
  external factory Request(
      {required int tabId, required String name, required dynamic options});
}

@JS()
@anonymous
class ErrorResponse {
  external set error(String error);
}

