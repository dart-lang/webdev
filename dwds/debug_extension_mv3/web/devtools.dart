// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library devtools;

import 'dart:html';
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
  // Create a Debugger panel for all internal apps:
  chrome.devtools.panels.create(
    isDevMode() ? '[DEV] Dart Debugger' : 'Dart Debugger',
    '',
    'panel.html',
    allowInterop((ExtensionPanel panel) => _onPanelAdded(panel, debugInfo)),
  );
  // Create an inspector panel for internal Flutter apps:
  final isFlutterApp = debugInfo.isFlutterApp ?? false;
  if (isFlutterApp) {
    chrome.devtools.panels.create(
      isDevMode() ? '[DEV] Flutter Inspector' : 'Flutter Inspector',
      '',
      'panel.html',
      allowInterop((ExtensionPanel panel) => _onPanelAdded(panel, debugInfo)),
    );
  }
  panelsExist = true;
}

void _onPanelAdded(ExtensionPanel panel, DebugInfo debugInfo) {
  panel.onShown.addListener(allowInterop((Window window) {
    if (window.origin != debugInfo.appOrigin) {
      debugWarn('Page at ${window.origin} is no longer a Dart app.');
      // TODO(elliette): Display banner that panel is not applicable. See:
      // https://stackoverflow.com/questions/18927147/how-to-close-destroy-chrome-devtools-extensionpanel-programmatically
    }
  }));
}
