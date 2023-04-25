// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/services/chrome_debug_exception.dart';
import 'package:dwds/src/utilities/domain.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

const _dartCoreLibrary = 'dart:core';
const _dartRuntimeLibrary = 'dart:_runtime';
const _dartInterceptorsLibrary = 'dart:_interceptors';

/// A hard-coded ClassRef for the Closure class.
final classRefForClosure = classRefFor(_dartCoreLibrary, InstanceKind.kClosure);

/// A hard-coded ClassRef for the String class.
final classRefForString = classRefFor(_dartCoreLibrary, InstanceKind.kString);

/// A hard-coded ClassRef for the Record class.
final classRefForRecord = classRefFor(_dartCoreLibrary, InstanceKind.kRecord);

/// A hard-coded ClassRef for the RecordType class.
final classRefForRecordType =
    classRefFor(_dartRuntimeLibrary, InstanceKind.kRecordType);

/// A hard-coded ClassRef for a (non-existent) class called Unknown.
final classRefForUnknown = classRefFor(_dartCoreLibrary, 'Unknown');

/// A hard-coded ClassRef for a JS exception.
///
/// Exceptions are instances of NativeError and its subtypes.
/// We detect their common base type in class metadata and replace their
/// classRef by hard-coded reference in instances and instance refs.
///
/// TODO(annagrin): this breaks on name changes for JS types.
/// https://github.com/dart-lang/sdk/issues/51583
final classRefForNativeJsError =
    classRefFor(_dartInterceptorsLibrary, 'NativeError');

String classMetaDataIdFor(String library, String? jsName) => '$library:$jsName';

/// Returns true for non-dart JavaScript classes.
///
/// TODO(annagrin): this breaks on name changes for JS types.
/// https://github.com/dart-lang/sdk/issues/51583
bool isNativeJsObjectRef(ClassRef? classRef) {
  final className = classRef?.name;
  final libraryUri = classRef?.library?.uri;
  // Non-dart JS objects are all instances of JavaScriptObject
  // and its subtypes with names that end with 'JavaScriptObject'.
  return className != null &&
      libraryUri == _dartInterceptorsLibrary &&
      className.endsWith('JavaScriptObject');
}

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
ClassRef classRefFor(Object? libraryId, Object? dartName) {
  final library = libraryId as String? ?? _dartCoreLibrary;
  final name = dartName as String?;
  return ClassRef(
    id: classIdFor(library, name),
    name: name,
    library: libraryRefFor(library),
  );
}

String classIdFor(String libraryId, String? name) => 'classes|$libraryId|$name';

enum ClassMetaDataKind {
  object,
  map,
  set,
  list,
  function,
  record,
  recordType,
  nativeError,
}

String toInstanceKind(ClassMetaDataKind kind) {
  switch (kind) {
    case ClassMetaDataKind.function:
      return InstanceKind.kClosure;
    case ClassMetaDataKind.list:
      return InstanceKind.kList;
    case ClassMetaDataKind.map:
      return InstanceKind.kMap;
    case ClassMetaDataKind.set:
      return InstanceKind.kSet;
    case ClassMetaDataKind.record:
      return InstanceKind.kRecord;
    case ClassMetaDataKind.recordType:
      return InstanceKind.kRecordType;
    case ClassMetaDataKind.nativeError:
    case ClassMetaDataKind.object:
    default:
      return InstanceKind.kPlainInstance;
  }
}

/// Meta data for a remote Dart class in Chrome.
class ClassMetaData {
  static final _logger = Logger('ClassMetadata');

  /// Instance kind.
  final String kind;

  /// Class id.
  ///
  /// Takes the form of 'libraryId:name'.
  final String id;

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
  String? get dartName => classRef.name;

  /// Class ref for the class metadata.
  final ClassRef classRef;

  factory ClassMetaData({
    Object? jsName,
    Object? length,
    required String kind,
    required ClassRef classRef,
  }) {
    final id = classMetaDataIdFor(classRef.library!.id!, jsName as String?);
    return ClassMetaData._(
      id,
      classRef,
      jsName,
      int.tryParse('$length'),
      kind,
    );
  }

  ClassMetaData._(
    this.id,
    this.classRef,
    this.jsName,
    this.length,
    this.kind,
  );

  /// Returns the [ClassMetaData] for the Chrome [remoteObject].
  ///
  /// Returns null if the [remoteObject] is not a Dart class.
  static Future<ClassMetaData?> metaDataFor(
    RemoteObject remoteObject,
    AppInspectorInterface inspector,
  ) async {
    try {
      final evalExpression = '''
      function(arg) {
        const sdk = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk');
        const dart = sdk.dart;
        const core = sdk.core;
        const interceptors = sdk._interceptors;
        const classObject = dart.getReifiedType(arg);
        const isFunction = classObject instanceof dart.AbstractFunctionType;
        const isRecord = classObject instanceof dart.RecordType;
        const isRecordType = dart.is(arg, dart.RecordType);
        const isNativeError = dart.is(arg, interceptors.NativeError);
        const result = {};
        var name = isFunction ? 'Function' : classObject.name;

        result['name'] = name;
        result['libraryId'] = dart.getLibraryUri(classObject);
        result['dartName'] = dart.typeName(classObject);
        result['isFunction'] = isFunction;
        result['isRecord'] = isRecord;
        result['isRecordType'] = isRecordType;
        result['isNativeError'] = isNativeError;
        result['length'] = arg['length'];

        if (isRecord) {
          result['name'] = 'Record';
          var shape = classObject.shape;
          var positionalCount = shape.positionals;
          var namedCount = shape.named == null ? 0 : shape.named.length;
          result['length'] = positionalCount + namedCount;
        }

        if (isRecordType) {
          result['name'] = 'RecordType';
          result['length'] = arg.types.length;
        }
        return result;
      }
    ''';

      final result = await inspector.jsCallFunctionOn(
        remoteObject,
        evalExpression,
        [remoteObject],
        returnByValue: true,
      );
      final metadata = result.value as Map;

      return ClassMetaData(
        jsName: metadata['name'],
        length: metadata['length'],
        kind: _getInstanceKind(metadata),
        classRef: _getClassRef(metadata),
      );
    } on ChromeDebugException catch (e, s) {
      _logger.fine(
        'Could not create class metadata for ${remoteObject.json}',
        e,
        s,
      );
      return null;
    }
  }
}

/// Find instance kind of an object from [metadata].
String _getInstanceKind(Map metadata) {
  final jsName = metadata['name'];
  final isFunction = metadata['isFunction'];
  final isRecord = metadata['isRecord'];
  final isRecordType = metadata['isRecordType'];

  if (jsName == '_HashSet') {
    return InstanceKind.kSet;
  }
  if (jsName == 'JSArray') {
    return InstanceKind.kList;
  }
  if (jsName == 'LinkedMap' || jsName == 'IdentityMap') {
    return InstanceKind.kMap;
  }
  if (isFunction) {
    return InstanceKind.kClosure;
  }
  if (isRecord) {
    return InstanceKind.kRecord;
  }
  if (isRecordType) {
    return InstanceKind.kRecordType;
  }
  return InstanceKind.kPlainInstance;
}

/// Find class ref of an object from [metadata].
ClassRef _getClassRef(Map metadata) {
  final dartName = metadata['dartName'];
  final library = metadata['libraryId'];
  final isRecord = metadata['isRecord'];
  final isRecordType = metadata['isRecordType'];
  final isNativeError = metadata['isNativeError'];

  if (isRecord) {
    return classRefForRecord;
  }
  if (isRecordType) {
    return classRefForRecordType;
  }
  if (isNativeError) {
    return classRefForNativeJsError;
  }

  return classRefFor(library, dartName);
}
