// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library auth_url;

import 'dart:html';
import 'dart:js';

import 'package:dwds/data/extension_request.dart';
import 'package:js/js.dart';

void main() {
  _writeAuthUrlToDom();
}

void _writeAuthUrlToDom() {
  final windowContext = JsObject.fromBrowserObject(window);
  final extensionUrl = windowContext['\$dartExtensionUri'];
  final authUrl = _constructAuthUrl(extensionUrl);
  document.documentElement?.setAttribute('data-dart-auth-url', authUrl);
}

Uri _constructAuthUrl(String extensionUrl) {
  final authUrl = Uri.parse(extensionUrl).replace(path: authenticationPath);
  if (authUrl.scheme == 'ws') {
    return authUrl.replace(scheme: 'http');
  }
  if (authUrl.scheme == 'wss') {
    return authUrl.replace(scheme: 'https');
  }
  return authUrl;
}
