// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library messages;

import 'dart:convert';

import 'package:js/js.dart';

class DebugInfo {
  final String? origin;
  final String? extensionUri;
  final String? appId;
  final String? instanceId;
  final String? entrypointPath;
  DebugInfo({
    this.origin,
    this.extensionUri,
    this.appId,
    this.instanceId,
    this.entrypointPath,
  });
  factory DebugInfo.fromJSON(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final origin = decoded['origin'] as String?;
    final extensionUri = decoded['extensionUri'] as String?;
    final appId = decoded['appId'] as String?;
    final instanceId = decoded['instanceId'] as String?;
    final entrypointPath = decoded['entrypointPath'] as String?;
    return DebugInfo(
      origin: origin,
      extensionUri: extensionUri,
      appId: appId,
      instanceId: instanceId,
      entrypointPath: entrypointPath,
    );
  }
  String toJSON() {
    return jsonEncode({
      'origin': origin,
      'extensionUri': extensionUri,
      'appId': appId,
      'instanceId': instanceId,
      'entrypointPath': entrypointPath,
    });
  }
}
