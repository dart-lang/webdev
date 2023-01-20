// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library authentication;

import 'dart:html';
import 'dart:js';

import 'package:js/js.dart';

import 'utils.dart';

void main() {
  _authenticateUser();
}

// Note: This is a workaround for b/26295128. We re-authenticate the user from
// the Dart app on every page reload, instead of re-authenticating from the
// service worker:
void _authenticateUser() async {
  final windowContext = JsObject.fromBrowserObject(window);
  final extensionUrl = windowContext['\$dartExtensionUri'];
  final authenticationSuccess = await authenticateUser(extensionUrl);
  document.dispatchEvent(CustomEvent(
    'dart-debug-extension-auth',
    detail: '$authenticationSuccess',
  ));
}
