// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../services/chrome_proxy_service.dart';
import 'remote_debugger.dart';

class ClassMetaData {
  final String name;
  final String libraryId;
  ClassMetaData(this.name, this.libraryId);
  String get id => '$libraryId:$name';
}

/// Returns the [ClassMetaData] for the Chrome [remoteObject].
///
/// Returns null if the [remoteObject] is not a Dart class.
Future<ClassMetaData> classMetaDataFor(
    RemoteDebugger remoteDebugger, RemoteObject remoteObject) async {
  try {
    var evalExpression = '''
      function(arg) {
        var sdkUtils = require('dart_sdk').dart;
        var classObject = sdkUtils.getType(arg);
        var result = {};
        result['name'] = classObject.name;
        result['libraryId'] = sdkUtils.getLibraryUri(classObject);
        return result;
      }
    ''';
    var arguments = [
      {'objectId': remoteObject.objectId}
    ];
    var result =
        await remoteDebugger.sendCommand('Runtime.callFunctionOn', params: {
      'functionDeclaration': evalExpression,
      'arguments': arguments,
      'objectId': remoteObject.objectId,
      'returnByValue': true,
    });
    handleErrorIfPresent(
      result,
      evalContents: evalExpression,
    );
    return ClassMetaData(result.result['result']['value']['name'] as String,
        result.result['result']['value']['libraryId'] as String);
  } on ChromeDebugException {
    return null;
  }
}
