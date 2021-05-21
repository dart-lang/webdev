// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

// @dart = 2.9

import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../dwds.dart' show ChromeDebugException;
import '../loaders/strategy.dart';
import '../utilities/domain.dart';
import '../utilities/shared.dart';
import 'inspector.dart';
import 'metadata/class.dart';

/// A hard-coded ClassRef for the Closure class.
final classRefForClosure = classRefFor('dart:core', 'Closure');

/// A hard-coded ClassRef for the String class.
final classRefForString = classRefFor('dart:core', InstanceKind.kString);

/// A hard-coded ClassRef for a (non-existent) class called Unknown.
final classRefForUnknown = classRefFor('dart:core', 'Unknown');

/// Returns a [ClassRef] for the provided library ID and class name.
ClassRef classRefFor(String libraryId, String name) =>
    ClassRef(id: 'classes|$libraryId|$name', name: name);

/// Keeps track of Dart classes available in the running application.
class ClassHelper extends Domain {
  /// Map of class ID to [Class].
  final _classes = <String, Class>{};

  ClassHelper(AppInspector Function() provider) : super(provider) {
    var staticClasses = [
      classRefForClosure,
      classRefForString,
      classRefForUnknown
    ];
    for (var classRef in staticClasses) {
      _classes[classRef.id] = Class(
          name: classRef.name,
          isAbstract: false,
          isConst: false,
          library: null,
          interfaces: [],
          fields: [],
          functions: [],
          subclasses: [],
          id: classRef.id,
          traceAllocations: false);
    }
  }

  /// Returns the [Class] that corresponds to the provided [objectId].
  ///
  /// If a corresponding class does not exist it will return null.
  Future<Class> forObjectId(String objectId) async {
    if (!objectId.startsWith('classes|')) return null;
    var clazz = _classes[objectId];
    if (clazz != null) return clazz;
    var splitId = objectId.split('|');
    var libraryId = splitId[1];
    if (libraryId == 'null') {
      throw UnsupportedError('unknown library: $libraryId');
    }
    var libraryRef = await inspector.libraryHelper.libraryRefFor(libraryId);
    if (libraryRef == null) {
      throw Exception('Could not find library: $libraryId');
    }
    var classRef = classRefFor(libraryId, splitId.last);
    clazz = await _constructClass(libraryRef, classRef);
    if (clazz == null) {
      throw Exception('Could not contruct class: $classRef');
    }
    return _classes[objectId] = clazz;
  }

  /// Constructs a [Class] instance for the provided [LibraryRef] and
  /// [ClassRef].
  Future<Class> _constructClass(
      LibraryRef libraryRef, ClassRef classRef) async {
    var rawName = classRef.name.split('<').first;
    var expression = '''
    (function() {
      ${globalLoadStrategy.loadLibrarySnippet(libraryRef.uri)}
      var result = {};
      var clazz = library["$rawName"];
      var descriptor = {
          'name': clazz.name,
          'dartName': sdkUtils.typeName(clazz)
        };

      // TODO(grouma) - we display all inherited methods since we don't provide
      // the superClass information. This is technically not correct.
      var proto = clazz.prototype;
      var methodNames = [];
      for (; proto != null; proto = Object.getPrototypeOf(proto)) {
        var methods = Object.getOwnPropertyNames(proto);
        for (var i = 0; i < methods.length; i++) {
          if (methodNames.indexOf(methods[i]) == -1
              && typeof Object.getOwnPropertyDescriptor(proto,methods[i])['value'] == 'function'
              && methods[i] != 'constructor') {
              methodNames.push(methods[i]);
          }
        }
        if (proto.constructor.name == 'Object') break;
      }

      descriptor['methods'] = {};
      for (var name of methodNames) {
        descriptor['methods'][name] = {
          // TODO(jakemac): how can we get actual const info?
          "isConst": false,
          "isStatic": false,
        }
      }
      // TODO(jakemac): static fields once ddc supports them
      var fields = sdkUtils.getFields(clazz);
      var fieldNames = fields ? Object.keys(fields) : [];
      descriptor['fields'] = {};
      for (var name of fieldNames) {
        var field = fields[name];
        var libraryUri = Object.getOwnPropertySymbols(fields[name]["type"])
        .find(x => x.description == "libraryUri");
        descriptor['fields'][name] = {
          // TODO(jakemac): how can we get actual const info?
          "isConst": false,
          "isFinal": field.isFinal,
          "isStatic": false,
          "classRefName": fields[name]["type"]["name"],
          "classRefDartName": sdkUtils.typeName(fields[name]["type"]),
          "classRefLibraryId" : field["type"][libraryUri],
        }
      }
      return descriptor;
    })()
    ''';

    RemoteObject result;
    try {
      result = await inspector.remoteDebugger.evaluate(
        expression,
        returnByValue: true,
        contextId: await inspector.contextId,
      );
    } on ExceptionDetails catch (e) {
      throw ChromeDebugException(e.json, evalContents: expression);
    }

    var classDescriptor = result.value as Map<String, dynamic>;
    var methodRefs = <FuncRef>[];
    var methodDescriptors = classDescriptor['methods'] as Map<String, dynamic>;
    methodDescriptors.forEach((name, descriptor) {
      var methodId = 'methods|${classRef.id}|$name';
      methodRefs.add(FuncRef(
          id: methodId,
          name: name,
          owner: classRef,
          isConst: descriptor['isConst'] as bool,
          isStatic: descriptor['isStatic'] as bool));
    });
    var fieldRefs = <FieldRef>[];
    var fieldDescriptors = classDescriptor['fields'] as Map<String, dynamic>;
    fieldDescriptors.forEach((name, descriptor) async {
      var classMetaData = ClassMetaData(
          jsName: descriptor['classRefName'],
          libraryId: descriptor['classRefLibraryId'],
          dartName: descriptor['classRefDartName']);
      fieldRefs.add(FieldRef(
          name: name,
          owner: classRef,
          declaredType: InstanceRef(
              identityHashCode: createId().hashCode,
              id: createId(),
              kind: InstanceKind.kType,
              classRef: classMetaData.classRef),
          isConst: descriptor['isConst'] as bool,
          isFinal: descriptor['isFinal'] as bool,
          isStatic: descriptor['isStatic'] as bool,
          id: createId()));
    });

    // TODO: Implement the rest of these
    // https://github.com/dart-lang/webdev/issues/176.
    return Class(
        name: classRef.name,
        isAbstract: false,
        isConst: false,
        library: libraryRef,
        interfaces: [],
        fields: fieldRefs,
        functions: methodRefs,
        subclasses: [],
        id: classRef.id,
        traceAllocations: false);
  }
}
