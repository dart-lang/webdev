// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:dwds/src/utilities/shared.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../services/chrome_proxy_service.dart';
 import 'remote_debugger.dart';

/// Meta data for a remote Dart class in Chrome.
class ClassMetaData {
  final String name;
  final String libraryId;
  ClassMetaData(this.name, this.libraryId);

  /// Returns the ID of the class.
  ///
  /// Takes the form of 'libraryId:name'.
  String get id => '$libraryId:$name';

  /// Returns the [ClassMetaData] for the Chrome [remoteObject].
  ///
  /// Returns null if the [remoteObject] is not a Dart class.
  static Future<ClassMetaData> metaDataFor(
      RemoteDebugger remoteDebugger, RemoteObject remoteObject) async {
    try {
      var evalExpression = '''
      function(arg) {
        var sdkUtils = $loadModule('dart_sdk').dart;
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
      // var result = inspector.callFunctionOn(remoteObject, evalExpression, arguments);
      var result = await remoteDebugger.sendCommand('Runtime.callFunctionOn', params: {
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
}

/// Meta data for a remote Dart function in Chrome.
class FunctionMetaData {
  final String name;
  FunctionMetaData(this.name);

  /// Returns the [FunctionMetaData] for the Chrome [remoteObject].
  static Future<FunctionMetaData> metaDataFor(
      RemoteDebugger remoteDebugger, RemoteObject remoteObject) async {
    var evalExpression = '''
      function(remoteObject) {
        var sdkUtils = $loadModule('dart_sdk').dart;
        var name = remoteObject.name;
        if(remoteObject._boundObject) {
         name = sdkUtils.getType(remoteObject._boundObject).name +
                 '.' + remoteObject._boundMethod.name;
        }
        return name;
      }
    ''';
    var arguments = [
      {'objectId': remoteObject.objectId}
    ];
    var response =
        await remoteDebugger.sendCommand('Runtime.callFunctionOn', params: {
      'functionDeclaration': evalExpression,
      'arguments': arguments,
      'objectId': remoteObject.objectId,
      'returnByValue': true,
    });
    handleErrorIfPresent(
      response,
      evalContents: evalExpression,
    );
    var name = response.result['result']['value'] as String;
    if (name.isEmpty) name = 'Closure';
    return FunctionMetaData(name);
  }
}
