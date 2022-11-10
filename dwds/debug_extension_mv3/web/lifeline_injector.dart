// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'chrome_api.dart';
import 'web_api.dart';

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
  if (enableDebugLogging) {
    // _logTimeAliveToTabConsole();
  }
}

void _logTimeAliveToTabConsole() {
  int timeElapsed = 0;
  Timer.periodic(const Duration(seconds: 30), (timer) {
    timeElapsed += 30;
    _logTime(timeElapsed);
  });
}

String _currentTime() {
  final date = DateTime.now();
  return '${date.hour}:${date.minute}';
}

void _logTime(int time) {
  final secs = time % 60;
  final mins = (time / 60).floor();
  _debugLog('Alive for $mins min $secs sec.');
}

void _debugLog(String msg) {
  if (enableDebugLogging) {
    console.log(msg);
  }
}

