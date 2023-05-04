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
enum RuntimeObjectKind {
  object,
  set,
  list,
  map,
  function,
  record,
  type,
  recordType,
  wrappedType,
  nativeError,
  nativeObject;

  static final _valueMap = {
    for (var v in values) v.toString(): v,
  };

  static RuntimeObjectKind from(String value) {
    final kind = _valueMap[value];
    if (kind == null) {
      throw StateError('Unknown runtime object kind: $value');
    }
    return kind;
  }

  String toInstanceKind() {
    return switch (this) {
      object || nativeObject || nativeError => InstanceKind.kPlainInstance,
      set => InstanceKind.kSet,
      list => InstanceKind.kList,
      map => InstanceKind.kMap,
      function => InstanceKind.kClosure,
      record => InstanceKind.kRecord,
      type || wrappedType => InstanceKind.kType,
      recordType => InstanceKind.kRecordType,
    };
  }
}

/// Meta data for a remote Dart class in Chrome.
class ClassMetaData {
  /// Runtime object kind.
  final RuntimeObjectKind runtimeKind;

  /// Class id.
  ///
  /// Takes the form of 'libraryId:name'.
  final String id;

  /// The name of the JS constructor for the object.
  ///
  /// This may be a constructor for a Dart, but it's still a JS name. For
  /// example, 'Number', 'JSArray', 'Object'.
  final String? jsName;

  /// Type name for Type instances.
  ///
  /// For example, 'int', 'String', 'MyClass', 'List<int>'.
  final String? typeName;

  /// The length of the object, if applicable.
  final int? length;

  /// The dart type name for the object.
  ///
  /// For example, 'int', 'List<String>', 'Null'
  String? get dartName => classRef.name;

  /// Class ref for the class metadata.
  final ClassRef classRef;

  /// Instance kind for vm service protocol.
  String get kind => runtimeKind.toInstanceKind();

  factory ClassMetaData({
    Object? jsName,
    Object? typeName,
    Object? length,
    required RuntimeObjectKind runtimeKind,
    required ClassRef classRef,
  }) {
    final id = classMetaDataIdFor(classRef.library!.id!, jsName as String?);
    return ClassMetaData._(
      id,
      classRef,
      jsName,
      typeName as String?,
      int.tryParse('$length'),
      runtimeKind,
    );
  }

  ClassMetaData._(
    this.id,
    this.classRef,
    this.jsName,
    this.typeName,
    this.length,
    this.runtimeKind,
  );
}

/// Metadata helper for objects and class refs.
///
/// Allows to get runtime metadata from DDC runtime
/// and provides functionality to detect some of the
/// runtime kinds of objects.
class ClassMetaDataHelper {
  static final _logger = Logger('ClassMetadata');

  final AppInspectorInterface _inspector;

  /// Runtime object kinds for class refs.
  final _runtimeObjectKinds = <String, RuntimeObjectKind>{};

  ClassMetaDataHelper(this._inspector);

  /// Returns the [ClassMetaData] for the Chrome [remoteObject].
  ///
  /// Returns null if the [remoteObject] is not a Dart class.
  Future<ClassMetaData?> metaDataFor(RemoteObject remoteObject) async {
    try {
      /// TODO(annagrin): this breaks on changes to internal
      /// type representation in DDC. Replace by runtime API.
      /// https://github.com/dart-lang/sdk/issues/51583
      final evalExpression = '''
      function(arg) {
        const sdk = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk');
        const dart = sdk.dart;
        const core = sdk.core;
        const interceptors = sdk._interceptors;
        const reifiedType = dart.getReifiedType(arg);

        const result = {};
        var name = reifiedType.name;

        result['name'] = name;
        result['libraryId'] = dart.getLibraryUri(reifiedType);
        result['dartName'] = dart.typeName(reifiedType);
        result['length'] = arg['length'];
        result['runtimeKind'] = '${RuntimeObjectKind.object}';

        if (name == '_HashSet') {
          result['runtimeKind'] = '${RuntimeObjectKind.set}';
        } else if (name == 'JSArray') {
          result['runtimeKind'] = '${RuntimeObjectKind.list}';
        } else if (name == 'LinkedMap' || name == 'IdentityMap') {
          result['runtimeKind'] = '${RuntimeObjectKind.map}';
        } else if (reifiedType instanceof dart.AbstractFunctionType) {
          result['runtimeKind'] = '${RuntimeObjectKind.function}';
          result['name'] = 'Function';
        } else if (reifiedType instanceof dart.RecordType) {
          result['runtimeKind'] = '${RuntimeObjectKind.record}';
          result['name'] = 'Record';
          result['libraryId'] = 'dart:core';
          result['dartName'] = 'Record';
          var shape = reifiedType.shape;
          var positionalCount = shape.positionals;
          var namedCount = shape.named == null ? 0 : shape.named.length;
          result['length'] = positionalCount + namedCount;
        } else if (arg instanceof dart._Type) {
          result['runtimeKind'] = '${RuntimeObjectKind.wrappedType}';
        } else if (arg instanceof dart.RecordType) {
          result['runtimeKind'] = '${RuntimeObjectKind.recordType}';
          result['name'] = 'RecordType';
          result['length'] = arg.types.length;
        } else if (dart.is(arg, core.Type)) {
          result['runtimeKind'] = '${RuntimeObjectKind.type}';
          var externalType = dart.wrapType(arg);
          result['typeName'] = dart.dsendRepl(externalType, "toString", []);
        } else if (dart.is(arg, interceptors.NativeError)) {
          result['runtimeKind'] = '${RuntimeObjectKind.nativeError}';
        } else if (dart.is(arg, interceptors.JavaScriptObject)) {
          result['runtimeKind'] = '${RuntimeObjectKind.nativeObject}';
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
      final typeName = metadata['typeName'];
      final dartName = metadata['dartName'];
      final library = metadata['libraryId'];
      final runtimeKind = RuntimeObjectKind.from(metadata['runtimeKind']);
      final length = metadata['length'];

      final classRef = classRefFor(library, dartName);
      _addRuntimeObjectKind(classRef, runtimeKind);

      return ClassMetaData(
        jsName: jsName,
        typeName: typeName,
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

  // Stores runtime object kind for class refs.
  void _addRuntimeObjectKind(
    ClassRef classRef,
    RuntimeObjectKind runtimeKind,
  ) {
    final id = classRef.id;
    if (id == null) {
      throw StateError('No classRef id for $classRef');
    }
    _runtimeObjectKinds[id] = runtimeKind;
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
