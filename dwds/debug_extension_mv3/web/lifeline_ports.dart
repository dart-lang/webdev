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
import 'debug_session.dart';
import 'logger.dart';
import 'utils.dart';

Port? _lifelinePort;
int? _lifelineTab;

Future<void> maybeCreateLifelinePort(int tabId) async {
  // This is only necessary for Manifest V3 extensions:
  if (!isMV3) return;
  // Don't create a lifeline port if we already have one (meaning another Dart
  // app is currently being debugged):
  if (_lifelinePort != null) {
    debugWarn('Port already exists.');
    return;
  }
  // Start the keep-alive logic when the port connects:
  chrome.runtime.onConnect.addListener(allowInterop(_keepLifelinePortAlive));
  // Inject the connection script into the current Dart tab, that way the tab
  // will connect to the port:
  debugLog('Creating lifeline port.');
  _lifelineTab = tabId;
  await injectScript('lifeline_connection.dart.js', tabId: tabId);
}

void maybeRemoveLifelinePort(int removedTabId) {
  // This is only necessary for Manifest V3 extensions:
  if (!isMV3) return;
  // If the removed Dart tab hosted the lifeline port connection, see if there
  // are any other Dart tabs to connect to. Otherwise disconnect the port.
  if (_lifelineTab == removedTabId) {
    if (existsActiveDebugSession) {
      _lifelineTab = latestAppBeingDebugged;
      debugLog('Reconnecting lifeline port to a new Dart tab: $_lifelineTab.');
      _reconnectToLifelinePort();
    } else {
      _lifelineTab = null;
      debugLog('No more Dart tabs, disconnecting from lifeline port.');
      _disconnectFromLifelinePort();
    }
  }
}

void _keepLifelinePortAlive(Port port) {
  final portName = port.name ?? '';
  if (portName != 'keepAlive') return;
  _lifelinePort = port;
  // Reconnect to the lifeline port every 5 minutes, as per:
  // https://bugs.chromium.org/p/chromium/issues/detail?id=1146434#c6
  Timer(Duration(minutes: 5), () {
    debugLog('5 minutes have elapsed, therefore reconnecting.');
    _reconnectToLifelinePort();
  });
}

void _reconnectToLifelinePort() {
  debugLog('Reconnecting...');
  if (_lifelinePort == null) {
    debugWarn('Could not find a lifeline port.');
    return;
  }
  if (_lifelineTab == null) {
    debugWarn('Could not find a lifeline tab.');
    return;
  }
  // Disconnect from the port, and then recreate the connection with the current
  // Dart tab:
  _disconnectFromLifelinePort();
  maybeCreateLifelinePort(_lifelineTab!);
  debugLog('Reconnection complete.');
}

void _disconnectFromLifelinePort() {
  debugLog('Disconnecting...');
  if (_lifelinePort != null) {
    _lifelinePort!.disconnect();
    _lifelinePort = null;
    debugLog('Disconnection complete.');
  }
}
