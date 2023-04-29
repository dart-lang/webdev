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

/// A hard-coded ClassRef for the Closure class.
final classRefForClosure = classRefFor(_dartCoreLibrary, InstanceKind.kClosure);

/// A hard-coded ClassRef for the String class.
final classRefForString = classRefFor(_dartCoreLibrary, InstanceKind.kString);

/// A hard-coded ClassRef for the Record class.
final classRefForRecord = classRefFor(_dartCoreLibrary, InstanceKind.kRecord);

/// A hard-coded ClassRef for the RecordType class.
final classRefForRecordType =
    classRefFor(_dartRuntimeLibrary, InstanceKind.kRecordType);

/// A hard-coded ClassRef for the Type class.
final classRefForType = classRefFor(_dartCoreLibrary, 'Type');

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
String classMetaDataIdFor(String library, String? jsName) => '$library:$jsName';

/// DDC runtime object kind.
///
/// Object kinds are determined using DDC runtime API and
/// are used to translate from JavaScript objects to their
/// vm service protocol representation.
class RuntimeObjectKind {
  static const String object = 'object';
  static const String set = 'set';
  static const String list = 'list';
  static const String map = 'map';
  static const String wrappedType = 'wrappedType';
  static const String function = 'function';
  static const String record = 'record';
  static const String type = 'type';
  static const String recordType = 'recordType';
  static const String nativeError = 'nativeError';
  static const String nativeObject = 'nativeObject';
}

/// Meta data for a remote Dart class in Chrome.
class ClassMetaData {
  /// Runtime object kind.
  final String runtimeKind;

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

  /// Instance kind for vm service protocol.
  String get kind => _toInstanceKind(runtimeKind);

  factory ClassMetaData({
    Object? jsName,
    Object? length,
    required String runtimeKind,
    required ClassRef classRef,
  }) {
    final id = classMetaDataIdFor(classRef.library!.id!, jsName as String?);
    return ClassMetaData._(
      id,
      classRef,
      jsName,
      int.tryParse('$length'),
      runtimeKind,
    );
  }

  ClassMetaData._(
    this.id,
    this.classRef,
    this.jsName,
    this.length,
    this.runtimeKind,
  );

  static String _toInstanceKind(String runtimeKind) {
    switch (runtimeKind) {
      case RuntimeObjectKind.function:
        return InstanceKind.kClosure;
      case RuntimeObjectKind.list:
        return InstanceKind.kList;
      case RuntimeObjectKind.map:
        return InstanceKind.kMap;
      case RuntimeObjectKind.set:
        return InstanceKind.kSet;
      case RuntimeObjectKind.record:
        return InstanceKind.kRecord;
      case RuntimeObjectKind.recordType:
        return InstanceKind.kRecordType;
      case RuntimeObjectKind.object:
      case RuntimeObjectKind.type:
      case RuntimeObjectKind.wrappedType:
      case RuntimeObjectKind.nativeError:
      case RuntimeObjectKind.nativeObject:
      default:
        return InstanceKind.kPlainInstance;
    }
  }
}

class ClassMetaDataHelper {
  static final _logger = Logger('ClassMetadata');

  final AppInspectorInterface _inspector;

  /// Runtime object kinds for class refs.
  final _runtimeObjectKinds = <String, String>{};

  ClassMetaDataHelper(this._inspector);

  /// Returns the [ClassMetaData] for the Chrome [remoteObject].
  ///
  /// Returns null if the [remoteObject] is not a Dart class.
  Future<ClassMetaData?> metaDataFor(RemoteObject remoteObject) async {
    try {
      /// TODO(annagrin): this breaks on changes internal
      /// type representation in DDC. Replace by runtime API.
      /// https://github.com/dart-lang/sdk/issues/51583
      final evalExpression = '''
      function(arg) {
        const sdk = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk');
        const dart = sdk.dart;
        const core = sdk.core;
        const interceptors = sdk._interceptors;
        const classObject = dart.getReifiedType(arg);

        const result = {};
        var name = classObject.name;

        result['name'] = name;
        result['libraryId'] = dart.getLibraryUri(classObject);
        result['dartName'] = dart.typeName(classObject);
        result['length'] = arg['length'];
        result['runtimeKind'] = '${RuntimeObjectKind.object}';

        if (name == '_HashSet') {
          result['runtimeKind'] = '${RuntimeObjectKind.set}';
        } else if (name == 'JSArray') {
          result['runtimeKind'] = '${RuntimeObjectKind.list}';
        } else if (name == 'LinkedMap' || name == 'IdentityMap') {
          result['runtimeKind'] = '${RuntimeObjectKind.map}';
        } else if (classObject instanceof dart.AbstractFunctionType) {
          result['runtimeKind'] = '${RuntimeObjectKind.function}';
          result['name'] = 'Function';
        } else if (classObject instanceof dart.RecordType) {
          result['runtimeKind'] = '${RuntimeObjectKind.record}';
          result['name'] = 'Record';
          var shape = classObject.shape;
          var positionalCount = shape.positionals;
          var namedCount = shape.named == null ? 0 : shape.named.length;
          result['length'] = positionalCount + namedCount;
        } else if (dart.is(arg, dart.RecordType)) {
          result['runtimeKind'] = '${RuntimeObjectKind.recordType}';
          result['name'] = 'RecordType';
          result['length'] = arg.types.length;
        } else if (name == 'Type') {
          result['runtimeKind'] = '${RuntimeObjectKind.type}';
        } else if (dart.is(arg, dart._Type)) {
          result['runtimeKind'] = '${RuntimeObjectKind.wrappedType}';
        } else if (dart.is(arg, interceptors.JavaScriptObject)) {
          result['runtimeKind'] = '${RuntimeObjectKind.nativeObject}';
        } else if (dart.is(arg, interceptors.NativeError)) {
          result['runtimeKind'] = '${RuntimeObjectKind.nativeError}';
        }
        return result;
      }
    ''';

      final result = await _inspector.jsCallFunctionOn(
        remoteObject,
        evalExpression,
        [remoteObject],
        returnByValue: true,
      );
      final metadata = result.value as Map;
      final jsName = metadata['name'];
      final dartName = metadata['dartName'];
      final library = metadata['libraryId'];
      final runtimeKind = metadata['runtimeKind'];
      final length = metadata['length'];

      // We hide internal types for some instance types.
      var classRef = classRefFor(library, dartName);
      if (runtimeKind == RuntimeObjectKind.record) {
        classRef = classRefForRecord;
      } else if (runtimeKind == RuntimeObjectKind.recordType) {
        classRef = classRefForRecordType;
      } else if (runtimeKind == RuntimeObjectKind.wrappedType) {
        classRef = classRefForType;
      }

      final id = classRef.id;
      if (id == null) {
        throw StateError('ClassRef id is null for $dartName');
      }
      _runtimeObjectKinds[id] = runtimeKind;

      return ClassMetaData(
        jsName: jsName,
        length: length,
        runtimeKind: runtimeKind,
        classRef: classRef,
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

  /// Returns true for non-dart JavaScript classes.
  bool isNativeJsObject(ClassRef? classRef) {
    final id = classRef?.id;
    return id != null &&
        _runtimeObjectKinds[id] == RuntimeObjectKind.nativeObject;
  }

  /// Returns true for non-dart JavaScript classes.
  bool isNativeJsError(ClassRef? classRef) {
    final id = classRef?.id;
    return id != null &&
        _runtimeObjectKinds[id] == RuntimeObjectKind.nativeError;
  }
}
