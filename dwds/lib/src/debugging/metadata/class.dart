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
const _dartInterceptorsLibrary = 'dart:_interceptors';

/// A hard-coded ClassRef for the Closure class.
final classRefForClosure = classRefFor(_dartCoreLibrary, InstanceKind.kClosure);

/// A hard-coded ClassRef for the String class.
final classRefForString = classRefFor(_dartCoreLibrary, InstanceKind.kString);

/// A hard-coded ClassRef for the Record class.
final classRefForRecord = classRefFor(_dartCoreLibrary, InstanceKind.kRecord);

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
ClassRef classRefFor(String libraryId, String? name) => ClassRef(
      id: classIdFor(libraryId, name),
      name: name,
      library: libraryRefFor(libraryId),
    );

String classIdFor(String libraryId, String? name) => 'classes|$libraryId|$name';

/// Meta data for a remote Dart class in Chrome.
class ClassMetaData {
  static final _logger = Logger('ClassMetadata');

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
  final String? dartName;

  /// Class ref for the class metadata.
  final ClassRef classRef;

  factory ClassMetaData({
    Object? jsName,
    Object? libraryId,
    Object? dartName,
    Object? length,
    bool isFunction = false,
    bool isRecord = false,
    bool isNativeError = false,
  }) {
    final jName = jsName as String?;
    final dName = dartName as String?;
    final library = libraryId as String? ?? _dartCoreLibrary;
    final id = '$library:$jName';

    final classRef = isRecord ? classRefForRecord : classRefFor(library, dName);

    return ClassMetaData._(
      id,
      classRef,
      jName,
      dName,
      int.tryParse('$length'),
      isFunction,
      isRecord,
      isNativeError,
    );
  }

  ClassMetaData._(
    this.id,
    this.classRef,
    this.jsName,
    this.dartName,
    this.length,
    this.isFunction,
    this.isRecord,
    this.isNativeError,
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
        const interceptors = sdk._interceptors;
        const classObject = dart.getReifiedType(arg);
        const isFunction = classObject instanceof dart.AbstractFunctionType;
        const isRecord = classObject instanceof dart.RecordType;
        const isNativeError = dart.is(arg, interceptors.NativeError);
        const result = {};
        var name = isFunction ? 'Function' : classObject.name;

        result['name'] = name;
        result['libraryId'] = dart.getLibraryUri(classObject);
        result['dartName'] = dart.typeName(classObject);
        result['isFunction'] = isFunction;
        result['isRecord'] = isRecord;
        result['isNativeError'] = isNativeError;
        result['length'] = arg['length'];

        if (isRecord) {
          result['name'] = 'Record';
          var shape = classObject.shape;
          var positionalCount = shape.positionals;
          var namedCount = shape.named == null ? 0 : shape.named.length;
          result['length'] = positionalCount + namedCount;
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
        libraryId: metadata['libraryId'],
        dartName: metadata['dartName'],
        isFunction: metadata['isFunction'],
        isRecord: metadata['isRecord'],
        isNativeError: metadata['isNativeError'],
        length: metadata['length'],
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

  /// True if this class refers to system maps, which are treated specially.
  ///
  /// Classes that implement Map or inherit from MapBase are still treated as
  /// plain objects.
  // TODO(alanknight): It may be that IdentityMap should not be treated as a
  // system map.
  bool get isSystemMap => jsName == 'LinkedMap' || jsName == 'IdentityMap';

  /// True if this class refers to system Lists, which are treated specially.
  bool get isSystemList => jsName == 'JSArray';

  bool get isSet => jsName == '_HashSet';

  /// True if this class refers to a function type.
  bool isFunction;

  /// True if this class refers to a record type.
  bool isRecord;

  /// True is this class refers to a native JS type.
  /// i.e. inherits from NativeError.
  bool isNativeError;
}
