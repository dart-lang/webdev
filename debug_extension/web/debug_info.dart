// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debug_info;

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
          ..appEntrypointPath = windowContext['\$dartEntrypointPath']
          ..appId = windowContext['\$dartAppId']
          ..appInstanceId = windowContext['\$dartAppInstanceId']
          ..appOrigin = window.location.origin
          ..appUrl = window.location.href
          ..extensionUrl = windowContext['\$dartExtensionUri']
          ..isInternalBuild = windowContext['\$isInternalBuild']
          ..isFlutterApp = windowContext['\$isFlutterApp'],
      ),
    ),
  );
}
