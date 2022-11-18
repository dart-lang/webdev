// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'chrome_api.dart';
import 'web_api.dart';

void main() async {
  _connectToLifelinePort();
}

void _connectToLifelinePort() {
  console.log(
      '[Dart Debug Extension] Connecting to lifeline port at ${_currentTime()}.');
  chrome.runtime.connect(
    /*extensionId=*/ null,
    ConnectInfo(name: 'keepAlive'),
  );
}

String _currentTime() {
  final date = DateTime.now();
  return '${date.hour}:${date.minute}::${date.second}';
}
