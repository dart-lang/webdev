// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library utils;

import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';

bool? _isDevMode;

bool isDevMode() {
  if (_isDevMode != null) {
    return _isDevMode!;
  }
  final extensionManifest = chrome.runtime.getManifest();
  final extensionName = getProperty(extensionManifest, 'name') ?? '';
  return extensionName.contains('DEV');
}
