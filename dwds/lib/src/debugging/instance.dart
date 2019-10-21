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

/// A hard-coded ClassRef for a (non-existent) class called Unknown.
final _classRefForUnknown = ClassRef(name: 'Unknown', id: createId());

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
    var properties = await _debugger.getProperties(remoteObject.objectId);
    var classRef = metaData.classRef;
    if (metaData.name == 'Function') {
      return _closureInstanceFor(remoteObject);
    } else if (metaData.name == 'JSArray') {
      return await _listInstanceFor(classRef, remoteObject, properties);
    } else if (metaData.name == 'LinkedMap' || metaData.name == 'IdentityMap') {
      return await _mapInstanceFor(classRef, remoteObject, properties);
    } else {
      return await _plainInstanceFor(classRef, remoteObject, properties);
    }
  }

  /// Create a bound field for [property] in an instance of [classRef].
  Future<BoundField> _fieldFor(Property property, ClassRef classRef) async {
    var instance = await _instanceRefForRemote(property.value);
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
  }

  /// Create a plain instance of [classRef] from [remoteObject] and the JS
  /// properties [properties].
  Future<Instance> _plainInstanceFor(ClassRef classRef,
      RemoteObject remoteObject, List<Property> properties) async {
    var dartProperties = await _dartFieldsFor(properties, remoteObject);
    var fields = await Future.wait(
        dartProperties.map<Future<BoundField>>((p) => _fieldFor(p, classRef)));
    fields = fields.toList()
      ..sort((a, b) => a.decl.name.compareTo(b.decl.name));
    var result = Instance(
        kind: InstanceKind.kPlainInstance,
        id: remoteObject.objectId,
        classRef: classRef)
      ..fields = fields;
    return result;
  }

  /// The associations for a Dart Map or IdentityMap.
  Future<List<MapAssociation>> _mapAssociations(RemoteObject map) async {
    var expression = '''
      function() {
        var sdkUtils = $loadModule('dart_sdk').dart;
        var entries = sdkUtils.dloadRepl(this, "entries");
        entries = sdkUtils.dsendRepl(entries, "toList", []);
        function asKeyValue(entry) {
          return {
            key: sdkUtils.dloadRepl(entry, "key"),
            value: sdkUtils.dloadRepl(entry, "value")
          }
        }
        return entries.map(asKeyValue);
      }
    ''';
    var keysAndValues = await inspector.jsCallFunctionOn(map, expression, [],
        returnByValue: true);
    var associations = <MapAssociation>[];
    for (var each in keysAndValues.value as List) {
      associations.add(MapAssociation()
        ..key = await instanceRefFor(each['key'])
        ..value = await instanceRefFor(each['value']));
    }
    return associations;
  }

  /// Create a Map instance with class [classRef] from [remoteObject].
  Future<Instance> _mapInstanceFor(
      ClassRef classRef, RemoteObject remoteObject, List<Property> _) async {
    // Maps are complicated, do an eval to get keys and values.
    var associations = await _mapAssociations(remoteObject);
    return Instance(
        kind: InstanceKind.kMap, id: remoteObject.objectId, classRef: classRef)
      ..length = associations.length
      ..associations = associations;
  }

  /// Create a List instance of [classRef] from [remoteObject] with the JS
  /// properties [properties].
  Future<Instance> _listInstanceFor(ClassRef classRef, RemoteObject remoteObject,
      List<Property> properties) async {
    var length = _lengthOf(properties);
    var indexed = properties.sublist(0, length);
    var fields = await Future.wait(indexed
        .map((property) async => await _instanceRefForRemote(property.value)));
    return Instance(
        kind: InstanceKind.kList, id: remoteObject.objectId, classRef: classRef)
      ..length = length
      ..elements = fields;
  }

  /// Return the value of the length attribute from [properties], if present.
  ///
  /// This is only applicable to Lists or Maps, where we expect a length
  /// attribute. Even if a plain instance happens to have a length field, we
  /// don't use it to determine the properties to display.
  int _lengthOf(List<Property> properties) {
    var lengthProperty = properties.firstWhere((p) => p.name == 'length');
    return lengthProperty.value.value as int;
  }

  /// Filter [allJsProperties] and return a list containing only those
  /// that correspond to Dart fields on [remoteObject].
  ///
  /// This only applies to objects with named fields, not Lists or Maps.
  Future<List<Property>> _dartFieldsFor(
      List<Property> allJsProperties, RemoteObject remoteObject) async {
    // An expression to find the field names from the types, extract both
    // private (named by symbols) and public (named by strings) and return them
    // as a comma-separated single string, so we can return it by value and not
    // need to make multiple round trips.
    //
    // For maps and lists it's more complicated. Treat the actual SDK versions
    // of these as special.
    // TODO(alanknight): Handle superclass fields.
    final fieldNameExpression = '''function() {
      const sdk = $loadModule("dart_sdk");
      const sdk_utils = sdk.dart;
      const fields = sdk_utils.getFields(sdk_utils.getType(this)) || [];
      if (!fields && (dart_sdk._interceptors.JSArray.is(this) || 
          dart_sdk._js_helper.InternalMap.is(this))) {
        // Trim off the 'length' property.
        const fields = allJsProperties.slice(0, allJsProperties.length -1);
        return fields.join(',');
      } 
      const privateFields = sdk_utils.getOwnPropertySymbols(fields);
      const nonSymbolNames = privateFields.map(sym => sym.description);
      const publicFieldNames = sdk_utils.getOwnPropertyNames(fields);
      return nonSymbolNames.concat(publicFieldNames).join(',');
    }
    ''';
    var allNames = (await inspector
            .jsCallFunctionOn(remoteObject, fieldNameExpression, []))
        .value as String;
    var names = allNames.split(',');
    // TODO(#761): Better support for large collections.
    return allJsProperties
        .where((property) => names.contains(property.name))
        .toList();
  }

  /// Create an InstanceRef for an object, which may be a RemoteObject, or may
  /// be something returned by value from Chrome, e.g. number, boolean, or
  /// String.
  Future<InstanceRef> instanceRefFor(Object value) {
    var remote = value is RemoteObject
        ? value
        : RemoteObject({'value': value, 'type': chromeType(value)});
    return _instanceRefForRemote(remote);
  }

  /// The Chrome type for a value.
  String chromeType(Object value) {
    if (value == null) return null;
    if (value is String) return 'string';
    if (value is num) return 'number';
    if (value is bool) return 'boolean';
    if (value is Function) return 'function';
    return 'object';
  }

  /// Create an [InstanceRef] for the given Chrome [remoteObject].
  Future<InstanceRef> _instanceRefForRemote(RemoteObject remoteObject) async {
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
        if (remoteObject.objectId == null) {
          return _primitiveInstance(InstanceKind.kNull, remoteObject);
        }
        var metaData = await ClassMetaData.metaDataFor(
            _remoteDebugger, remoteObject, inspector);
        if (metaData == null) return null;
        if (metaData.name == 'JSArray') {
          return InstanceRef(
              kind: InstanceKind.kList,
              id: remoteObject.objectId,
              classRef: metaData.classRef)
            ..length = metaData.length;
        }
        if (metaData.name == 'LinkedMap' || metaData.name == 'IdentityMap') {
          return InstanceRef(
              kind: InstanceKind.kMap,
              id: remoteObject.objectId,
              classRef: metaData.classRef)
            ..length = metaData.length;
        }
        return InstanceRef(
            kind: InstanceKind.kPlainInstance,
            id: remoteObject.objectId,
            classRef: metaData.classRef);
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
              // TODO(alanknight): The right ClassRef
              owner: _classRefForUnknown,
              isConst: false,
              isStatic: false)
          ..closureContext = (ContextRef()..length = 0);
      default:
        // Return null for an unsupported type. This is likely a JS construct.
        return null;
    }
  }
}
