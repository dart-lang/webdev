// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'chrome_api.dart';
import 'web_api.dart';

// Switch to true to enable debug logs.
// TODO(elliette): Enable / disable with flag while building the extension.
final enableDebugLogging = true;

void main() async {
  _connectToLifelinePort();
}

void _connectToLifelinePort() {
  _debugLog('Connecting to lifeline port at ${_currentTime()}');
  chrome.runtime.connect(
    /*extensionId=*/ null,
    ConnectInfo(name: 'keepAlive'),
  );
}

String _currentTime() {
  final date = DateTime.now();
  return '${date.hour}:${date.minute}::${date.second}';
}

void _debugLog(String msg) {
  if (enableDebugLogging) {
    console.log(msg);
  }
}
