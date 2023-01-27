// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:dwds/src/utilities/domain.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../debugging/remote_debugger.dart';
import '../../loaders/strategy.dart';
import '../../services/chrome_debug_exception.dart';

const _dartCoreLibrary = 'dart:core';

/// A hard-coded ClassRef for the Closure class.
final classRefForClosure = classRefFor(_dartCoreLibrary, 'Closure');

/// A hard-coded ClassRef for the String class.
final classRefForString = classRefFor(_dartCoreLibrary, InstanceKind.kString);

/// A hard-coded ClassRef for a (non-existent) class called Unknown.
final classRefForUnknown = classRefFor(_dartCoreLibrary, 'Unknown');

///  A hard-coded LibraryRef for a a dart:core library.
final libraryRefForCore = LibraryRef(
  id: _dartCoreLibrary,
  name: _dartCoreLibrary,
  uri: _dartCoreLibrary,
);

/// Returns a [LibraryRef] for the provided library ID and class name.
LibraryRef libraryRefFor(String libraryId) => LibraryRef(
      id: libraryId,
      name: libraryId,
      uri: libraryId,
    );

/// Returns a [ClassRef] for the provided library ID and class name.
ClassRef classRefFor(String libraryId, String? name) => ClassRef(
      id: 'classes|$libraryId|$name',
      name: name,
      library: libraryRefFor(libraryId),
    );

/// Meta data for a remote Dart class in Chrome.
class ClassMetaData {
  /// The name of the JS constructor for the object.
  ///
  /// This may be a constructor for a Dart, but it's still a JS name. For
  /// example, 'Number', 'JSArray', 'Object'.
  final String? jsName;

  /// The length of the object, if applicable.
  final int? length;

  /// The dart type name for the object.
  ///
  /// For example, 'int', 'List<String>', 'Null'
  final String? dartName;

  /// The library identifier, which is the URI of the library.
  final String libraryId;

  factory ClassMetaData({
    Object? jsName,
    Object? libraryId,
    Object? dartName,
    Object? length,
    bool isFunction = false,
    bool isRecord = false,
  }) {
    return ClassMetaData._(
      jsName as String?,
      libraryId as String? ?? _dartCoreLibrary,
      dartName as String?,
      int.tryParse('$length'),
      isFunction,
      isRecord,
    );
  }

  ClassMetaData._(
    this.jsName,
    this.libraryId,
    this.dartName,
    this.length,
    this.isFunction,
    this.isRecord,
  );

  /// Returns the ID of the class.
  ///
  /// Takes the form of 'libraryId:name'.
  String get id => '$libraryId:$jsName';

  /// Returns the [ClassMetaData] for the Chrome [remoteObject].
  ///
  /// Returns null if the [remoteObject] is not a Dart class.
  static Future<ClassMetaData?> metaDataFor(RemoteDebugger remoteDebugger,
      RemoteObject remoteObject, AppInspectorInterface inspector) async {
    try {
      final evalExpression = '''
      function(arg) {
        const sdkUtils = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk').dart;
        const classObject = sdkUtils.getReifiedType(arg);
        const isFunction = sdkUtils.AbstractFunctionType.is(classObject);
        const isRecord = sdkUtils.RecordType.is(classObject);
        const result = {};
        var name = isFunction ? 'Function' : classObject.name;
        
        result['name'] = name;
        result['libraryId'] = sdkUtils.getLibraryUri(classObject);
        result['dartName'] = sdkUtils.typeName(classObject);
        result['isFunction'] = isFunction;
        result['isRecord'] = isRecord;
        result['length'] = arg['length'];

        if (isRecord) {
          result['name'] = 'Record';
          var positionals = classObject.shape.positionals;
          var named = classObject.shape.named == null
            ? 0
            : classObject.shape.named.length;
          result['length'] = positionals + named;
        }

        return result;
      }
    ''';
      final result = await inspector.jsCallFunctionOn(
          remoteObject, evalExpression, [remoteObject],
          returnByValue: true);
      final metadata = result.value as Map;
      return ClassMetaData(
        jsName: metadata['name'],
        libraryId: metadata['libraryId'],
        dartName: metadata['dartName'],
        isFunction: metadata['isFunction'],
        isRecord: metadata['isRecord'],
        length: metadata['length'],
      );
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

  /// True if this class refers to a function type.
  bool isFunction;

  /// True if this class refers to a record type.
  bool isRecord;
}
