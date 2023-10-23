// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library popup;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:dwds/data/debug_info.dart';
import 'package:js/js.dart';

import 'data_serializers.dart';
import 'data_types.dart';
import 'logger.dart';
import 'messaging.dart';
import 'storage.dart';
import 'utils.dart';

const _hiddenClass = 'hidden';
const _launchDevToolsButtonId = 'launchDevToolsButton';
const _copyButtonId = 'copyButton';
const _appIdSpanId = 'appId';
const _appIdContainerId = 'appIdContainer';
const _loadingSpinnerId = "loadingSpinner";
const _copiedSuccessId = "copiedSuccess";

Future<int?> get _tabId async {
  final tab = await activeTab;
  return tab?.id;
}

String? _appId;

Future<void> main() async {
  _registerListeners();

  debugLog('inserting app id');
  final inserted = await _insertAppId();
  debugLog('done inserting app id');
  if (inserted) {
    _updateElementVisibility(_appIdContainerId, visible: true);
  }
  // _updateElementVisibility(_loadingSpinnerId, visible: false);
}

void _registerListeners() {
  final launchDevToolsButton =
      document.getElementById(_launchDevToolsButtonId) as ButtonElement;
  launchDevToolsButton.addEventListener('click', _launchDevTools);

  final copyButton = document.getElementById(_copyButtonId) as ButtonElement;
  copyButton.addEventListener('click', _copyAppId);
}

Future<bool> _insertAppId() async {
  final tabId = await _tabId;
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: tabId,
  );
  if (debugInfo == null || tabId == null) return false;
  // final isInternalBuild = debugInfo.isInternalBuild ?? false;
  // if (isInternalBuild) {
  final _appId = _createAppId(debugInfo: debugInfo, tabId: tabId);
  final appIdSpan = document.getElementById(_appIdSpanId) as SpanElement;
  appIdSpan.setInnerHtml(_appId);
  // }
  // return isInternalBuild;
  return true;
}

String _createAppId({required DebugInfo debugInfo, required int tabId}) {
  final workspaceName = debugInfo.workspaceName;
  return '$workspaceName-$tabId';
}

Future<void> _launchDevTools(Event _) async {
  final tabId = await _tabId;
  final json = jsonEncode(
    serializers.serialize(
      DebugStateChange(
        (b) => b
          ..tabId = tabId
          ..newState = DebugStateChange.startDebugging,
      ),
    ),
  );
  await sendRuntimeMessage(
    type: MessageType.debugStateChange,
    body: json,
    sender: Script.debuggerPanel, // change to popup
    recipient: Script.background,
  );
}

void _copyAppId(Event _) {
  if (_appId == null) return;
  final clipboard = window.navigator.clipboard;
  if (clipboard == null) return;
  clipboard.writeText(_appId!);
  _updateElementVisibility(_copiedSuccessId, visible: true);
}

void _updateElementVisibility(String elementId, {required bool visible}) {
  final element = document.getElementById(elementId);
  if (element == null) return;
  if (visible) {
    element.classes.remove(_hiddenClass);
  } else {
    element.classes.add(_hiddenClass);
  }
}
