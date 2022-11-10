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
int? lifelineTab;
final dartTabs = <int>[];

void maybeCreateLifelinePort(int tabId) {
  if (lifelinePort != null) {
    _debugWarn('Port already exists.');
    dartTabs.add(tabId);
    _debugLog('Dart tabs are: $dartTabs');
    return null;
  }

  chrome.runtime.onConnect.addListener(allowInterop(_keepLifelinePortAlive));

  _debugLog('Creating lifeline port.');
  lifelineTab = tabId;
  chrome.scripting.executeScript(
    InjectDetails(
      target: Target(tabId: tabId),
      files: ['lifeline_injector.dart.js'],
    ),
    /*callback*/ null,
  );
}

void maybeRemoveLifelinePort(int tabId) {
  _debugLog('Maybe removing $tabId from $dartTabs...');
  dartTabs.remove(tabId);
  _debugLog('Dart tabs are now $dartTabs');
  if (lifelineTab == tabId) {
    if (dartTabs.isEmpty) {
      lifelineTab = null;
      _debugLog('No more Dart tabs, disconnecting');
      _disconnectFromLifelinePort();
    } else {
      lifelineTab = dartTabs.last;
      _debugLog('Reconnecting to a new Dart tab: $lifelineTab');
      _reconnectToLifelinePort();
    }
  }
}

void _keepLifelinePortAlive(Port port) {
  final portName = port.name ?? '';
  if (portName != 'keepAlive') return;
  lifelinePort = port;
  // Time from https://bugs.chromium.org/p/chromium/issues/detail?id=1146434#c6
  Timer(Duration(minutes: 5), () {
    _debugLog('5 minutes have elapsed, therefore reconnecting.');
    _reconnectToLifelinePort();
  });
  // port.onDisconnect
  //     .addListener(allowInterop((_) => _reconnectToLifelinePort()));
}

void _disconnectFromLifelinePort() {
  _debugLog('Disconnecting...');
  if (lifelinePort != null) {
    lifelinePort!.disconnect();
    lifelinePort = null;
    _debugLog('Disconnection complete.');
  }
}

void _reconnectToLifelinePort() {
  _debugLog('Reconnecting...');
  if (lifelinePort == null) {
    _debugWarn('Could not find a lifeline port.');
    return;
  }
  if (lifelineTab == null) {
    _debugWarn('Could not find a lifeline tab.');
    return;
  }

  _disconnectFromLifelinePort();
  maybeCreateLifelinePort(lifelineTab!);
  _debugLog('Reconnection complete.');
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
