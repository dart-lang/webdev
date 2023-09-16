// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library cider_connection;

import 'dart:convert';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'storage.dart';

const ciderPortName = 'cider';

enum CiderMessageType {
  startDebug,
  stopDebug,
  error,
}

Port? _ciderPort;

// The only site allowed to connect with this extension is Cider.
//
// The allowed URIs for Cider are set in the externally_connectable field in the
//manifest.json.
void handleCiderConnectRequest(Port port) {
  if (port.name == ciderPortName) {
    _ciderPort = port;

    port.onMessage.addListener(
      allowInterop(_handleMessageFromCider),
    );
  }
}

Future<void> _handleMessageFromCider(dynamic message, Port _) async {
  if (message! is String) {
    // TODO: send error to Cider.
    return;
  }

  final decoded = jsonDecode(message as String) as Map<String, dynamic>;
  final messageType = decoded['messageType'] as String?;
  final messageBody = decoded['messageBody'] as String?;

  if (messageType == CiderMessageType.startDebug.name) {
    await _startDebugging(workspaceName: messageBody);
  } else if (messageType == CiderMessageType.stopDebug.name) {
    // TODO: stop debugging.
  }
}

Future<void> _startDebugging({String? workspaceName}) async {
  if (workspaceName == null) {
    // TODO: send error to Cider.
    return;
  }

  final tabs = await _findDartTabsForWorkspace(workspaceName);

  if (tabs.isEmpty) {
    // TODO: send error to Cider.
    return;
  }
  if (tabs.length > 1) {
    // TODO: send error to Cider.
    return;
  }
  if (tabs.first == null) {
    // TODO: send error to Cider.
    return;
  }

  // TODO: call attachDebugger with Cider V as trigger.
}

Future<List<int?>> _findDartTabsForWorkspace(String workspaceName) async {
  final allTabsInfo = await fetchAllStorageObjectsOfType<DebugInfo>(
    type: StorageObject.debugInfo,
  );
  final tabIds = allTabsInfo
      .where(
        (debugInfo) => debugInfo.workspaceName == workspaceName,
      )
      .map(
        (info) => info.tabId,
      )
      .toList();
  return tabIds;
}
