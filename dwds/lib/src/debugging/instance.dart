// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../utilities/conversions.dart';
import '../utilities/domain.dart';
import '../utilities/objects.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'debugger.dart';
import 'inspector.dart';
import 'metadata.dart';
import 'remote_debugger.dart';

/// Creates an [InstanceRef] for a primitive [RemoteObject].
InstanceRef _primitiveInstance(String kind, RemoteObject remoteObject) {
  var classRef = ClassRef(
      // TODO(grouma) - is this ID correct?
      id: 'dart:core:${remoteObject?.type}',
      name: kind);
  return InstanceRef(
      kind: kind, classRef: classRef, id: dartIdFor(remoteObject?.value))
    ..valueAsString = '${remoteObject?.value}';
}

/// A hard-coded ClassRef for the String class.
final _classRefForString =
    ClassRef(id: 'dart:core:String', name: InstanceKind.kString);

/// A hard-coded ClassRef for the Closure class.
// TODO(grouma) - orgnaize our static classRefs better.
final _classRefForClosure = ClassRef(name: 'Closure', id: createId());

/// Contains a set of methods for getting [Instance]s and [InstanceRef]s.
class InstanceHelper extends Domain {
  final Debugger _debugger;
  final RemoteDebugger _remoteDebugger;

  InstanceHelper(
      this._debugger, this._remoteDebugger, AppInspector Function() provider)
      : super(provider);

  Future<Instance> _stringInstanceFor(RemoteObject remoteObject) async {
    var actualString = stringFromDartId(remoteObject.objectId);
    return Instance(
        kind: InstanceKind.kString,
        classRef: _classRefForString,
        id: createId())
      ..valueAsString = actualString
      ..length = actualString.length;
  }

  Future<Instance> _closureInstanceFor(RemoteObject remoteObject) async {
    var result = Instance(
        kind: InstanceKind.kClosure,
        id: remoteObject.objectId,
        classRef: _classRefForClosure);
    return result;
  }

  /// Create an [Instance] for the given [remoteObject].
  ///
  /// Does a remote eval to get instance information. Returns null if there
  /// isn't a corresponding instance.
  Future<Instance> instanceFor(RemoteObject remoteObject) async {
    if (isStringId(remoteObject.objectId)) {
      return _stringInstanceFor(remoteObject);
    }
    var metaData = await ClassMetaData.metaDataFor(
        _remoteDebugger, remoteObject, inspector);
    if (metaData.name == 'Function') {
      return _closureInstanceFor(remoteObject);
    } else {
      var classRef = ClassRef(id: metaData.id, name: metaData.name);
      var properties = await _debugger.getProperties(remoteObject.objectId);
      var dartProperties = await dartPropertiesFor(properties, remoteObject);
      var fields = await Future.wait(
          dartProperties.map<Future<BoundField>>((property) async {
        var instance = await instanceRefFor(property.value);
        return BoundField()
          ..decl = (FieldRef(
              // TODO(grouma) - Convert JS name to Dart.
              name: property.name,
              declaredType: (InstanceRef(
                  kind: InstanceKind.kType,
                  classRef: instance.classRef,
                  id: createId())),
              owner: classRef,
              // TODO(grouma) - Fill these in.
              isConst: false,
              isFinal: false,
              isStatic: false,
              id: createId()))
          ..value = instance;
      }));
      fields.sort((a, b) => a.decl.name.compareTo(b.decl.name));
      var result = Instance(
          kind: InstanceKind.kPlainInstance,
          id: remoteObject.objectId,
          classRef: classRef)
        ..fields = fields;
      return result;
    }
  }

  /// Filter [allJsProperties] and return a list containing only those
  /// that correspond to Dart fields on the object.
  Future<List<Property>> dartPropertiesFor(
      List<Property> allJsProperties, RemoteObject remoteObject) async {
    // An expression to find the field names from the types, extract both
    // private (named by symbols) and public (named by strings) and return them
    // as a comma-separated single string, so we can return it by value and not
    // need to make multiple round trips.
    // TODO(alanknight): Handle superclass fields.
    final fieldNameExpression = '''function() {
      const sdk_utils = $loadModule("dart_sdk").dart;
      const fields = sdk_utils.getFields(sdk_utils.getType(this));
      const privateFields = Object.getOwnPropertySymbols(fields);
      const nonSymbolNames = privateFields.map(sym => sym.description);
      const publicFieldNames = Object.getOwnPropertyNames(fields);
      return nonSymbolNames.concat(publicFieldNames).join(',');
    }
    ''';
    var allNames = (await inspector
            .jsCallFunctionOn(remoteObject, fieldNameExpression, []))
        .value as String;
    var names = allNames.split(',');
    return allJsProperties
        .where((property) => names.contains(property.name))
        .toList();
  }

  /// Create an [InstanceRef] for the given Chrome [remoteObject].
  Future<InstanceRef> instanceRefFor(RemoteObject remoteObject) async {
    // If we have a null result, treat it as a reference to null.
    if (remoteObject == null) {
      return _primitiveInstance(InstanceKind.kNull, remoteObject);
    }
    switch (remoteObject.type) {
      case 'string':
        return InstanceRef(
            id: dartIdFor(remoteObject.value),
            classRef: _classRefForString,
            kind: InstanceKind.kString)
          ..valueAsString = remoteObject.value as String;
      case 'number':
        return _primitiveInstance(InstanceKind.kDouble, remoteObject);
      case 'boolean':
        return _primitiveInstance(InstanceKind.kBool, remoteObject);
      case 'undefined':
        return _primitiveInstance(InstanceKind.kNull, remoteObject);
      case 'object':
        if (remoteObject.type == 'object' && remoteObject.objectId == null) {
          return _primitiveInstance(InstanceKind.kNull, remoteObject);
        }
        var metaData = await ClassMetaData.metaDataFor(
            _remoteDebugger, remoteObject, inspector);
        if (metaData == null) return null;
        return InstanceRef(
            kind: InstanceKind.kPlainInstance,
            id: remoteObject.objectId,
            classRef: ClassRef(name: metaData.name, id: metaData.id));
      case 'function':
        var functionMetaData =
            await FunctionMetaData.metaDataFor(_remoteDebugger, remoteObject);
        return InstanceRef(
            kind: InstanceKind.kClosure,
            id: remoteObject.objectId,
            classRef: _classRefForClosure)
          // TODO(grouma) - fill this in properly.
          ..closureFunction = FuncRef(
              name: functionMetaData.name,
              id: createId(),
              owner: null,
              isConst: false,
              isStatic: false)
          ..closureContext = (ContextRef()..length = 0);
      default:
        // Return null for an unsupported type. This is likely a JS construct.
        return null;
    }
  }
}
