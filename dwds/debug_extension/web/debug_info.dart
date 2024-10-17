// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library;

import 'dart:convert';
import 'dart:html';
import 'dart:js';

import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/serializers.dart';
import 'package:js/js.dart';

void main() {
  final debugInfoJson = _readDartDebugInfo();
  document.dispatchEvent(CustomEvent('dart-app-ready', detail: debugInfoJson));
}

String _readDartDebugInfo() {
  final windowContext = JsObject.fromBrowserObject(window);

  return jsonEncode(
    serializers.serialize(
      DebugInfo(
        (b) => b
          ..appEntrypointPath = windowContext['\$dartEntrypointPath'] as String?
          ..appId = windowContext['\$dartAppId'] as String?
          ..appInstanceId = windowContext['\$dartAppInstanceId'] as String?
          ..appOrigin = window.location.origin
          ..appUrl = window.location.href
          ..extensionUrl = windowContext['\$dartExtensionUri'] as String?
          ..isInternalBuild = windowContext['\$isInternalBuild'] as bool?
          ..isFlutterApp = windowContext['\$isFlutterApp'] as bool?,
      ),
    ),
  );
}
