// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;

class ScriptNotFound implements Exception {
  final String scriptPath;
  final shelf.Response response;

  ScriptNotFound(this.scriptPath, this.response) : super();

  @override
  String toString() => '''
Failed to load script at path: $scriptPath

Response status code: ${response.statusCode}
''';
}
