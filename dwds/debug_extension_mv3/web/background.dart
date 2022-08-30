// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'web_api.dart';

void main() {
  console.log('Running Dart Debug Extension.');
  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop((_) {
    console.log('Detected click on the Dart Debug Extension icon.');
  }));
}
