// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library cider_connection;

import 'dart:convert';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'debug_session.dart';
import 'logger.dart';
import 'storage.dart';

const ciderPortName = 'cider';

enum CiderMessageType {
  startDebugRequest,
  startDebugResponse,
  stopDebugRequest,
  stopDebugResponse,
  error,
}

enum CiderErrorType {
  invalidRequest,
  noWorkspace,
  noDartTab,
  multipleDartTabs,
  chromeError,
  internalError,
}

Port? _ciderPort;

// The only site allowed to connect with this extension is Cider.
//
// The allowed URIs for Cider are set in the externally_connectable field in the
// manifest.json.
void handleCiderConnectRequest(Port port) {
  if (port.name == ciderPortName) {
    _ciderPort = port;

    port.onMessage.addListener(
      allowInterop(_handleMessageFromCider),
    );
  }
}

// Sends a message to the Cider-connected port.
void sendMessageToCider({
  required CiderMessageType messageType,
  String? messageBody,
}) {
  if (_ciderPort == null) return;
  final message = jsonEncode({
    'messageType': messageType.name,
    'messageBody': messageBody,
  });
  _ciderPort!.postMessage(message);
}

// Sends an error message to the Cider-connected port.
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
  _ciderPort!.postMessage(message);
}

Future<void> _handleMessageFromCider(dynamic message, Port _) async {
  if (message is! String) {
    sendErrorMessageToCider(
      errorType: CiderErrorType.invalidRequest,
      errorDetails: 'Expected request to be a string: $message',
    );
    return;
  }

  final decoded = jsonDecode(message) as Map<String, dynamic>;
  final messageType = decoded['messageType'] as String?;
  final messageBody = decoded['messageBody'] as String?;

  if (messageType == CiderMessageType.startDebugRequest.name) {
    await _startDebugging(workspaceName: messageBody);
  } else if (messageType == CiderMessageType.stopDebugRequest.name) {
    await _stopDebugging(workspaceName: messageBody);
  }
}

Future<void> _startDebugging({String? workspaceName}) async {
  if (workspaceName == null) {
    _sendNoWorkspaceError();
    return;
  }

  final dartTab = await _findDartTabIdForWorkspace(workspaceName);
  if (dartTab != null) {
    // TODO(https://github.com/dart-lang/webdev/issues/2198): When debugging
    // with Cider, disable debugging with DevTools.
    await attachDebugger(dartTab, trigger: Trigger.cider);
  }
}

Future<void> _stopDebugging({String? workspaceName}) async {
  if (workspaceName == null) {
    _sendNoWorkspaceError();
    return;
  }

  final dartTab = await _findDartTabIdForWorkspace(workspaceName);
  if (dartTab == null) return;
  final successfullyDetached = await detachDebugger(
    dartTab,
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

void _sendNoWorkspaceError() {
  sendErrorMessageToCider(
    errorType: CiderErrorType.noWorkspace,
    errorDetails: 'Cannot find a debuggable Dart tab without a workspace',
  );
}

Future<int?> _findDartTabIdForWorkspace(String workspaceName) async {
  final allTabsInfo = await fetchAllStorageObjectsOfType<DebugInfo>(
    type: StorageObject.debugInfo,
  );
  final dartTabIds = allTabsInfo
      .where(
        (debugInfo) => debugInfo.workspaceName == workspaceName,
      )
      .map(
        (info) => info.tabId,
      )
      .toList();

  if (dartTabIds.isEmpty) {
    sendErrorMessageToCider(
      errorType: CiderErrorType.noDartTab,
      errorDetails: 'No debuggable Dart tabs found.',
    );
    return null;
  }
  if (dartTabIds.length > 1) {
    sendErrorMessageToCider(
      errorType: CiderErrorType.noDartTab,
      errorDetails: 'Too many debuggable Dart tabs found.',
    );
    return null;
  }
  final tabId = dartTabIds.first;
  if (tabId == null) {
    sendErrorMessageToCider(
      errorType: CiderErrorType.chromeError,
      errorDetails: 'Debuggable Dart tab is null.',
    );
    return null;
  }

  return tabId;
}
