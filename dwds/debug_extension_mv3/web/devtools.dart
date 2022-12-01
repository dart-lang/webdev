// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library detector;

import 'dart:html';
import 'dart:js_util';
import 'package:js/js.dart';
import 'package:dwds/data/debug_info.dart';

import 'chrome_api.dart';
import 'logger.dart';
import 'storage.dart';
import 'utils.dart';


bool panelsExist = false;

void main() async {
  _registerListeners();
  _maybeCreatePanels();
}

void _registerListeners() {
  chrome.storage.onChanged.addListener(allowInterop((
    Object _,
    String storageArea,
  ) {
    if (storageArea != 'session') return;
    _maybeCreatePanels();
  }));
}

void _maybeCreatePanels() async {
  if (panelsExist) return;
  final tabId = chrome.devtools.inspectedWindow.tabId;
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: tabId,
  );
  if (debugInfo == null) return;
  final isInternalBuild = debugInfo.isInternalBuild ?? false;
  if (!isInternalBuild) return;
  // Create a Debugger panel:
  chrome.devtools.panels.create(
    isDevMode() ? '[DEV] Dart Debugger' : 'Dart Debugger',
    '',
    'panel.html',
    allowInterop(_onDebuggerPanelAdded),
  );
    // Create an inspector panel:
  final isFlutterApp = debugInfo.isFlutterApp ?? false;
  if (isFlutterApp) {
    chrome.devtools.panels.create(
      isDevMode() ? '[DEV] Flutter Inspector' : 'Flutter Inspector',
      '',
      'panel.html',
      allowInterop(_onInspectorPanelAdded),
    );
  }
  panelsExist = true;
}

void _onDebuggerPanelAdded(ExtensionPanel debuggerPanel) {
  debuggerPanel.onShown.addListener(allowInterop((Window window) {
    debugLog('shown and window is ${window.origin}');
  }));
  debuggerPanel.onHidden.addListener(allowInterop(() {
    debugLog('hidden');
  }));
}

void _onInspectorPanelAdded(ExtensionPanel inspectorPanel) {
  // TODO(elliette) Implement.
}
