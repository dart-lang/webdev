// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'debugger.dart';
import 'metadata.dart';
import 'remote_debugger.dart';

/// JS field names to ignore when constructing a Dart [Instance].
const _namesToIgnore = <String>{
  'constructor',
  'noSuchMethod',
  'runtimeType',
  'toString',
  '_equals',
  '__defineGetter__',
  '__defineSetter__',
  '__lookupGetter__',
  '__lookupSetter__',
  '__proto__',
  'classGetter',
  'hasOwnProperty',
  'hashCode',
  'isPrototypeOf',
  'propertyIsEnumerable',
  'toLocaleString',
  'valueOf',
  '_identityHashCode'
};

/// Create an [Instance] for the given [objectId].
///
/// Returns null if there isn't a corresponding instance.
Future<Instance> instanceFor(
    Debugger debugger, RemoteDebugger remoteDebugger, String objectId) async {
  var remoteObject = RemoteObject({'objectId': objectId});
  var metaData = await classMetaDataFor(remoteDebugger, remoteObject);
  var classRef = ClassRef()
    ..id = metaData.id
    ..name = metaData.name;
  var properties = await debugger.getProperties(objectId);
  var fields = await Future.wait(
      properties.map<Future<BoundField>>((property) async => BoundField()
        ..decl = (FieldRef()
          // TODO(grouma) - Convert JS name to Dart.
          ..name = property.name
          ..owner = classRef
          ..declaredType = (InstanceRef()..classRef = ClassRef()))
        ..value = await instanceRefFor(remoteDebugger, property.value)));
  fields = fields
      .where((f) => f.value != null && !_namesToIgnore.contains(f.decl.name))
      .toList()
        ..sort((a, b) => a.decl.name.compareTo(b.decl.name));
  var result = Instance()
    ..kind = InstanceKind.kPlainInstance
    ..id = objectId
    ..fields = fields
    ..classRef = classRef;
  return result;
}

/// Create an [InstanceRef] for the given Chrome [remoteObject].
Future<InstanceRef> instanceRefFor(
    RemoteDebugger remoteDebugger, RemoteObject remoteObject) async {
  // If we have a null result, treat it as a reference to null.
  if (remoteObject == null) {
    return _primitiveInstance(InstanceKind.kNull, remoteObject);
  }
  switch (remoteObject.type) {
    case 'string':
      return _primitiveInstance(InstanceKind.kString, remoteObject);
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
      var metaData = await classMetaDataFor(remoteDebugger, remoteObject);
      if (metaData == null) return null;
      return InstanceRef()
        ..kind = InstanceKind.kPlainInstance
        ..id = remoteObject.objectId
        ..classRef = (ClassRef()
          ..name = metaData.name
          ..id = '${metaData.libraryId}:${metaData.name}');
    case 'function':
      var crudeAttemptAtName = remoteObject.description.split('(').first;
      return InstanceRef()
        ..kind = InstanceKind.kPlainInstance
        ..id = remoteObject.objectId
        ..valueAsString = crudeAttemptAtName
        ..classRef = ClassRef();
    default:
      // Return null for an unsupported type. This is likely a JS construct.
      return null;
  }
}

/// Creates an [InstanceRef] for a primitive [RemoteObject].
InstanceRef _primitiveInstance(String kind, RemoteObject remoteObject) {
  var classRef = ClassRef()
    ..id = 'dart:core:${remoteObject.type}'
    ..name = kind;
  return InstanceRef()
    ..valueAsString = '${remoteObject.value}'
    ..classRef = classRef
    ..kind = kind;
}
