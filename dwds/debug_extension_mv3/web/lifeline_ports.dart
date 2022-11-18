// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Keeps the background service worker alive for the duration of a Dart debug
// session by using the workaround described in:
// https://bugs.chromium.org/p/chromium/issues/detail?id=1152255#c21
@JS()
library lifeline_ports;

import 'dart:async';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'web_api.dart';

// Switch to true to enable debug logs.
// TODO(elliette): Enable / disable with flag while building the extension.
final enableDebugLogging = true;

Port? lifelinePort;
int? lifelineTab;
final dartTabs = <int>{};

void maybeCreateLifelinePort(int tabId) {
  // Keep track of current Dart tabs that are being debugged. This way if one of
  // them is closed, we can reconnect the lifeline port to another one:
  dartTabs.add(tabId);
  _debugLog('Dart tabs are: $dartTabs');
  // Don't create a lifeline port if we already have one (meaning another Dart
  // app is currently being debugged):
  if (lifelinePort != null) {
    _debugWarn('Port already exists.');
    return;
  }
  // Start the keep-alive logic when the port connects:
  chrome.runtime.onConnect.addListener(allowInterop(_keepLifelinePortAlive));
  // Inject the connection script into the current Dart tab, that way the tab
  // will connect to the port:
  _debugLog('Creating lifeline port.');
  lifelineTab = tabId;
  chrome.scripting.executeScript(
    InjectDetails(
      target: Target(tabId: tabId),
      files: ['lifeline_connection.dart.js'],
    ),
    /*callback*/ null,
  );
}

void maybeRemoveLifelinePort(int removedTabId) {
  final removedDartTab = dartTabs.remove(removedTabId);
  // If the removed tab was not a Dart tab, return early.
  if (!removedDartTab) return;
  _debugLog('Removed tab $removedTabId, Dart tabs are now $dartTabs.');
  // If the removed Dart tab hosted the lifeline port connection, see if there
  // are any other Dart tabs to connect to. Otherwise disconnect the port.
  if (lifelineTab == removedTabId) {
    if (dartTabs.isEmpty) {
      lifelineTab = null;
      _debugLog('No more Dart tabs, disconnecting from lifeline port.');
      _disconnectFromLifelinePort();
    } else {
      lifelineTab = dartTabs.last;
      _debugLog('Reconnecting lifeline port to a new Dart tab: $lifelineTab.');
      _reconnectToLifelinePort();
    }
  }
}

void _keepLifelinePortAlive(Port port) {
  final portName = port.name ?? '';
  if (portName != 'keepAlive') return;
  lifelinePort = port;
  // Reconnect to the lifeline port every 5 minutes, as per:
  // https://bugs.chromium.org/p/chromium/issues/detail?id=1146434#c6
  Timer(Duration(minutes: 5), () {
    _debugLog('5 minutes have elapsed, therefore reconnecting.');
    _reconnectToLifelinePort();
  });
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
  // Disconnect from the port, and then recreate the connection with the current
  // Dart tab:
  _disconnectFromLifelinePort();
  maybeCreateLifelinePort(lifelineTab!);
  _debugLog('Reconnection complete.');
}

void _disconnectFromLifelinePort() {
  _debugLog('Disconnecting...');
  if (lifelinePort != null) {
    lifelinePort!.disconnect();
    lifelinePort = null;
    _debugLog('Disconnection complete.');
  }
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
