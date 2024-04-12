// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library cider_connection;

import 'dart:convert';
import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'debug_session.dart';
import 'logger.dart';
import 'storage.dart';
import 'utils.dart';

/// Used to identify messages passed to/from Cider.
///
/// This must match the key defined in the Cider extension.
const _ciderDartMessageKey = 'CIDER_DART';

/// Defines the message types that can be passed to/from Cider.
///
/// The types must match those defined by ChromeExtensionMessageType in the
/// Cider extension.
enum CiderMessageType {
  connected,
  error,
  inspectorUrlResponse,
  inspectorUrlRequest,
  ping,
  pong,
  startDebugResponse,
  startDebugRequest,
  stopDebugResponse,
  stopDebugRequest,
}

/// Defines the error types that can be sent to Cider.
///
/// The types must match those defined by ChromeExtensionErrorType in the
/// Cider extension.
enum CiderErrorType {
  internalError,
  invalidRequest,
  noAppId,
}

const _ciderPortName = 'cider';
Port? _ciderPort;

/// Handles a connect request from Cider.
///
/// The only site allowed to connect with this extension is Cider. The allowed
/// URIs for Cider are set in the externally_connectable field in the manifest.
void handleCiderConnectRequest(Port port) {
  if (port.name == _ciderPortName) {
    debugLog('Received connect request from Cider', verbose: true);
    _ciderPort = port;

    port.onMessage.addListener(
      allowInterop(_handleMessageFromCider),
    );

    sendMessageToCider(messageType: CiderMessageType.connected);
  }
}

/// Sends a message to the Cider-connected port.
void sendMessageToCider({
  required CiderMessageType messageType,
  String? messageBody,
}) {
  if (_ciderPort == null) return;
  final message = jsonEncode({
    'messageType': messageType.name,
    'messageBody': messageBody,
  });
  _sendMessageToCider(message);
}

/// Sends an error message to the Cider-connected port.
void sendErrorMessageToCider({
  required CiderErrorType errorType,
  String? errorDetails,
}) {
  debugWarn('CiderError.${errorType.name} $errorDetails');
  if (_ciderPort == null) return;
  final message = jsonEncode({
    'messageType': CiderMessageType.error.name,
    'errorType': errorType.name,
    'messageBody': errorDetails,
  });
  _sendMessageToCider(message);
}

void _sendMessageToCider(String json) {
  final message = {
    'key': _ciderDartMessageKey,
    'json': json,
  };
  _ciderPort!.postMessage(jsify(message));
}

Future<void> _handleMessageFromCider(dynamic message, Port _) async {
  final key = getProperty(message, 'key');
  final json = getProperty(message, 'json');
  if (key != _ciderDartMessageKey || json is! String) {
    sendErrorMessageToCider(
      errorType: CiderErrorType.invalidRequest,
      errorDetails: 'Invalid message format: $message',
    );
    return;
  }

  final decoded = jsonDecode(json) as Map<String, dynamic>;
  final messageType = decoded['messageType'] as String?;
  final messageBody = decoded['messageBody'] as String?;

  if (messageType == CiderMessageType.startDebugRequest.name) {
    await _startDebugging(appId: messageBody);
  } else if (messageType == CiderMessageType.stopDebugRequest.name) {
    await _stopDebugging(appId: messageBody);
  } else if (messageType == CiderMessageType.inspectorUrlRequest.name) {
    await _sendInspectorUrl(appId: messageBody);
  } else if (messageType == CiderMessageType.ping.name) {
    sendMessageToCider(messageType: CiderMessageType.pong);
  }
}

Future<void> _startDebugging({String? appId}) async {
  if (appId == null) {
    _sendNoAppIdError();
    return;
  }
  final tabId = _tabId(appId);
  // TODO(https://github.com/dart-lang/webdev/issues/2198): When debugging
  // with Cider, disable debugging with DevTools.
  debugLog('Attach debugger to Cider', verbose: true);
  await attachDebugger(tabId, trigger: Trigger.cider);
}

Future<void> _stopDebugging({String? appId}) async {
  if (appId == null) {
    _sendNoAppIdError();
    return;
  }
  final tabId = _tabId(appId);

  final successfullyDetached = await detachDebugger(
    tabId,
    type: TabType.dartApp,
    reason: DetachReason.canceledByUser,
  );

  if (successfullyDetached) {
    sendMessageToCider(messageType: CiderMessageType.stopDebugResponse);
  } else {
    sendErrorMessageToCider(
      errorType: CiderErrorType.internalError,
      errorDetails: 'Unable to detach debugger.',
    );
  }
}

Future<void> _sendInspectorUrl({String? appId}) async {
  if (appId == null) {
    _sendNoAppIdError();
    return;
  }
  final tabId = _tabId(appId);
  final alreadyDebugging = isActiveDebugSession(tabId);
  if (!alreadyDebugging) {
    sendErrorMessageToCider(
      errorType: CiderErrorType.invalidRequest,
      errorDetails:
          'Cannot send the inspector URL before the debugger has been attached.',
    );
    return;
  }
  final devToolsUri = await fetchStorageObject<String>(
    type: StorageObject.devToolsUri,
    tabId: tabId,
  );
  if (devToolsUri == null) {
    sendErrorMessageToCider(
      errorType: CiderErrorType.internalError,
      errorDetails: 'Failed to fetch the DevTools URI for the inspector.',
    );
    return;
  }
  final inspectorUrl = addQueryParameters(
    devToolsUri,
    queryParameters: {
      'embed': 'true',
      'page': 'inspector',
    },
  );
  sendMessageToCider(
    messageType: CiderMessageType.inspectorUrlResponse,
    messageBody: inspectorUrl,
  );
}

int _tabId(String appId) {
  // The suffix "-f" is used to tell Cider that this is a Flutter app.
  if (appId.endsWith('-f')) {
    appId = appId.substring(0, appId.length - 2);
  }
  final tabId = appId.split('-').last;
  return int.parse(tabId);
}

void _sendNoAppIdError() {
  sendErrorMessageToCider(
    errorType: CiderErrorType.noAppId,
    errorDetails: 'Cannot find a debuggable Dart tab without an app ID',
  );
}
