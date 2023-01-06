// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library cross_extension_communication;

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_types.dart';
import 'debug_session.dart';
import 'logger.dart';
import 'storage.dart';
import 'web_api.dart';

const _angularDartDevToolsId = 'nbkbficgbembimioedhceniahniffgpl';

// A set of events to forward to the AngularDart DevTools extension.
final _eventsForAngularDartDevTools = {
  'Overlay.inspectNodeRequested',
  'dwds.encodedUri',
};

void handleMessagesFromAngularDartDevTools(
    dynamic jsRequest, MessageSender sender, Function sendResponse) async {
  if (jsRequest == null) return;
  final message = jsRequest as ExternalExtensionMessage;
  if (message.name == 'chrome.debugger.sendCommand') {
    _forwardCommandToChromeDebugger(message, sendResponse);
  } else if (message.name == 'dwds.encodedUri') {
    _respondWithEncodedUri(message.tabId, sendResponse);
  } else if (message.name == 'dwds.startDebugging') {
    attachDebugger(message.tabId, trigger: Trigger.angularDartDevTools);
    sendResponse(true);
  } else {
    sendResponse(
        ErrorResponse()..error = 'Unknown message name: ${message.name}');
  }
}

void maybeForwardMessageToAngularDartDevTools(
    {required String method, required dynamic params, required int tabId}) {
  if (!_eventsForAngularDartDevTools.contains(method)) return;

  final message = method.startsWith('dwds')
      ? _dwdsEventMessage(method: method, params: params, tabId: tabId)
      : _debugEventMessage(method: method, params: params, tabId: tabId);

  _forwardMessageToAngularDartDevTools(message);
}

void _forwardCommandToChromeDebugger(
    ExternalExtensionMessage message, Function sendResponse) {
  try {
    final options = message.options as SendCommandOptions;
    chrome.debugger.sendCommand(
      Debuggee(tabId: message.tabId),
      options.method,
      options.commandParams,
      allowInterop(
          ([result]) => _respondWithChromeResult(result, sendResponse)),
    );
  } catch (e) {
    sendResponse(ErrorResponse()..error = '$e');
  }
}

void _respondWithChromeResult(Object? chromeResult, Function sendResponse) {
  // No result indicates that an error occurred.
  if (chromeResult == null) {
    sendResponse(ErrorResponse()
      ..error = JSON.stringify(
        chrome.runtime.lastError ?? 'Unknown error.',
      ));
  } else {
    sendResponse(chromeResult);
  }
}

void _respondWithEncodedUri(int tabId, Function sendResponse) async {
  final encodedUri = await fetchStorageObject<EncodedUri>(
      type: StorageObject.encodedUri, tabId: tabId);
  sendResponse(encodedUri ?? '');
}

void _forwardMessageToAngularDartDevTools(ExternalExtensionMessage message) {
  chrome.runtime.sendMessage(
    _angularDartDevToolsId,
    message,
    /* options */ null,
    allowInterop(([result]) => _checkForErrors(result, message.name)),
  );
}

void _checkForErrors(Object? chromeResult, String messageName) {
  // No result indicates that an error occurred.
  if (chromeResult == null) {
    final errorMessage = chrome.runtime.lastError?.message ?? 'Unknown error.';
    debugWarn('Error forwarding $messageName: $errorMessage');
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

// This message is used for cross-extension communication between this extension
// and the AngularDart DevTools extension.
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
class ErrorResponse {
  external set error(String error);
}
