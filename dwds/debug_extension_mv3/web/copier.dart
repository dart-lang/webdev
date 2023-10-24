// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library copier;

import 'dart:html';

import 'package:js/js.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {}

void _copyAppId(String appId) {
  final clipboard = window.navigator.clipboard;
  if (clipboard == null) return;
  clipboard.writeText(appId);
  _showCopiedMessage(appId);
}

void _showCopiedMessage(String appId) {}
