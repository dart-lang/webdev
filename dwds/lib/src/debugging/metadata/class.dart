// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../debugging/classes.dart';
import '../../debugging/inspector.dart';
import '../../debugging/remote_debugger.dart';
import '../../loaders/strategy.dart';
import '../../services/chrome_proxy_service.dart';
import '../../utilities/wrapped_service.dart';

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
        dartName as String, int.tryParse('$length'));
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
    // TODO: We should cache ClassRef info based on remoteObject.className. This
    // would save ~one call per JS property, and significantly reduce the work
    // to populate JS frames.

    try {
      var evalExpression = '''
      function(arg) {
        const sdkUtils = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk').dart;
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
