// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library lifelinePorts;

import 'dart:async';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'web_api.dart';

/// Switch to true for debug logging.
bool enableDebugLogging = true;

Port? lifelinePort;
int? id;

void createLifelinePortForTab(int tabId) async {
  chrome.runtime.onConnect.addListener(allowInterop(_keepLifelinePortAlive));

  if (lifelinePort != null) {
    _debugWarn('Port already exists.');
    return;
  }

  _debugLog('Creating lifeline port.');
  id = tabId;
  chrome.scripting.executeScript(
    InjectDetails(
      target: Target(tabId: tabId),
      files: ['lifeline_injector.dart.js'],
    ),
    /*callback*/ null,
  );
}

void _keepLifelinePortAlive(Port port) {
  final portName = port.name ?? '';
  if (portName != 'keepAlive') return;
  lifelinePort = port;
  // Time from https://bugs.chromium.org/p/chromium/issues/detail?id=1146434#c6
  Timer(Duration(minutes: 5), () {
    _reconnectToLifelinePort(port);
  });
  port.onDisconnect.addListener(allowInterop(_reconnectToLifelinePort));
}

void _reconnectToLifelinePort(Port port) {
  _debugLog('Reconnecting...');
  if (lifelinePort == null) {
    _debugWarn('Could not find lifeline port.');
    return;
  }
  lifelinePort = null;
  port.disconnect();
  createLifelinePortForTab(id!);
}

void _debugLog(String msg) {
  if (enableDebugLogging) {
    console.log(msg);
  }
}

void _debugWarn(String msg) {
  if (enableDebugLogging) {
    console.warn(msg);
  }
}