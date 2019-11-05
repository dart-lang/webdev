// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../debugging/classes.dart';
import '../debugging/inspector.dart';
import '../services/chrome_proxy_service.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'remote_debugger.dart';

/// Meta data for a remote Dart class in Chrome.
class ClassMetaData {
  /// The name of the JS constructor for the object.
  ///
  /// This may be a constructor for a Dart, but it's still a JS name. For
  /// example, 'Number', 'JSArray', 'Object'.
  final String jsName;

  /// The length of the object, if applicable.
  final int length;

  /// The dart type name for the object.
  ///
  /// For example, 'int', 'List<String>', 'Null'
  final String dartName;

  /// The library identifier, which is the URI of the library.
  final String libraryId;

  factory ClassMetaData(
      {Object jsName, Object libraryId, Object dartName, Object length}) {
    return ClassMetaData._(jsName as String, libraryId as String,
        dartName as String, length as int);
  }

  ClassMetaData._(this.jsName, this.libraryId, this.dartName, this.length);

  /// Returns the ID of the class.
  ///
  /// Takes the form of 'libraryId:name'.
  String get id => '$libraryId:$jsName';

  /// Returns the [ClassMetaData] for the Chrome [remoteObject].
  ///
  /// Returns null if the [remoteObject] is not a Dart class.
  static Future<ClassMetaData> metaDataFor(RemoteDebugger remoteDebugger,
      RemoteObject remoteObject, AppInspector inspector) async {
    try {
      var evalExpression = '''
      function(arg) {
        const sdkUtils = $loadModule('dart_sdk').dart;
        const classObject = sdkUtils.getReifiedType(arg);
        const isFunction = sdkUtils.AbstractFunctionType.is(classObject);
        const result = {};
        result['name'] = isFunction ? 'Function' : classObject.name;
        result['dartName'] = sdkUtils.typeName(classObject);
        result['length'] = arg['length'];
        result['libraryId'] = sdkUtils.getLibraryUri(classObject);
        return result;
      }
    ''';
      var result = await inspector.jsCallFunctionOn(
          remoteObject, evalExpression, [remoteObject],
          returnByValue: true);
      var metadata = result.value as Map;
      return ClassMetaData(
          jsName: metadata['name'],
          libraryId: metadata['libraryId'],
          dartName: metadata['dartName'],
          length: metadata['length']);
    } on ChromeDebugException {
      return null;
    }
  }

  /// Return a [ClassRef] appropriate to this metadata.
  ClassRef get classRef => classRefFor(libraryId, dartName);

  /// True if this class refers to system maps, which are treated specially.
  ///
  /// Classes that implement Map or inherit from MapBase are still treated as
  /// plain objects.
  // TODO(alanknight): It may be that IdentityMap should not be treated as a
  // system map.
  bool get isSystemMap => jsName == 'LinkedMap' || jsName == 'IdentityMap';

  /// True if this class refers to system Lists, which are treated specially.
  bool get isSystemList => jsName == 'JSArray';
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
