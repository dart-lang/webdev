// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:math';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../loaders/strategy.dart';
import '../utilities/conversions.dart';
import '../utilities/domain.dart';
import '../utilities/objects.dart';
import '../utilities/shared.dart';
import '../utilities/wrapped_service.dart';
import 'classes.dart';
import 'inspector.dart';
import 'metadata/class.dart';
import 'metadata/function.dart';

/// Contains a set of methods for getting [Instance]s and [InstanceRef]s.
class InstanceHelper extends Domain {
  InstanceHelper(AppInspector Function() provider) : super(provider);

  static final InstanceRef kNullInstanceRef =
      _primitiveInstanceRef(InstanceKind.kNull, null);

  /// Creates an [InstanceRef] for a primitive [RemoteObject].
  static InstanceRef _primitiveInstanceRef(
      String kind, RemoteObject remoteObject) {
    var classRef = classRefFor('dart:core', kind);
    return InstanceRef(
        kind: kind, classRef: classRef, id: dartIdFor(remoteObject?.value))
      ..valueAsString = '${remoteObject?.value}';
  }

  /// Creates an [Instance] for a primitive [RemoteObject].
  Instance _primitiveInstance(String kind, RemoteObject remote) {
    if (remote?.objectId == null) return null;
    return Instance(
        id: remote.objectId,
        kind: kind,
        classRef: classRefFor('dart:core', kind))
      ..valueAsString = '${remote.value}';
  }

  Instance _stringInstanceFor(
      RemoteObject remoteObject, int offset, int count) {
    // TODO(#777) Consider a way of not passing the whole string around (in the
    // ID) in order to find a substring.
    var fullString = stringFromDartId(remoteObject.objectId);
    var preview = fullString;
    var truncated = false;
    if (offset != null || count != null) {
      truncated = true;
      var start = offset ?? 0;
      var end = count == null ? null : min(start + count, fullString.length);
      preview = fullString.substring(start, end);
    }
    return Instance(
        kind: InstanceKind.kString, classRef: classRefForString, id: createId())
      ..valueAsString = preview
      ..valueAsStringIsTruncated = truncated
      ..length = fullString.length
      ..count = (truncated ? preview.length : null)
      ..offset = (truncated ? offset : null);
  }

  Future<Instance> _closureInstanceFor(RemoteObject remoteObject) async {
    var result = Instance(
        kind: InstanceKind.kClosure,
        id: remoteObject.objectId,
        classRef: classRefForClosure);
    return result;
  }

  /// Create an [Instance] for the given [remoteObject].
  ///
  /// Does a remote eval to get instance information. Returns null if there
  /// isn't a corresponding instance. For enumerable objects, [offset] and
  /// [count] allow retrieving a sub-range of properties.
  Future<Instance> instanceFor(RemoteObject remoteObject,
      {int offset, int count}) async {
    var primitive = _primitiveInstanceOrNull(remoteObject, offset, count);
    if (primitive != null) {
      return primitive;
    }

    // TODO: This is checking the JS object ID for the dart pattern we use for
    // VM objects, which seems wrong (and, we catch 'string' types above).
    if (isStringId(remoteObject.objectId)) {
      return _stringInstanceFor(remoteObject, offset, count);
    }

    var metaData = await ClassMetaData.metaDataFor(
        inspector.remoteDebugger, remoteObject, inspector);
    var classRef = metaData.classRef;
    if (metaData.jsName == 'Function') {
      return _closureInstanceFor(remoteObject);
    }

    var properties = await inspector.debugger.getProperties(
        remoteObject.objectId,
        offset: offset,
        count: count,
        length: metaData.length);
    if (metaData.isSystemList) {
      return await _listInstanceFor(
          classRef, remoteObject, properties, offset, count);
    } else if (metaData.isSystemMap) {
      return await _mapInstanceFor(
          classRef, remoteObject, properties, offset, count);
    } else {
      return await _plainInstanceFor(classRef, remoteObject, properties);
    }
  }

  /// If [remoteObject] represents a primitive, return an [Instance] for it,
  /// otherwise return null.
  Instance _primitiveInstanceOrNull(
      RemoteObject remoteObject, int offset, int count) {
    switch (remoteObject?.type ?? 'undefined') {
      case 'string':
        return _stringInstanceFor(remoteObject, offset, count);
      case 'number':
        return _primitiveInstance(InstanceKind.kDouble, remoteObject);
      case 'boolean':
        return _primitiveInstance(InstanceKind.kBool, remoteObject);
      case 'undefined':
        return _primitiveInstance(InstanceKind.kNull, remoteObject);
      default:
        return null;
    }
  }

  /// Create a bound field for [property] in an instance of [classRef].
  Future<BoundField> _fieldFor(Property property, ClassRef classRef) async {
    var instance = await _instanceRefForRemote(property.value);
    return BoundField(
        decl: FieldRef(
          // TODO(grouma) - Convert JS name to Dart.
          name: property.name,
          declaredType: InstanceRef(
              kind: InstanceKind.kType,
              classRef: instance.classRef,
              id: createId()),
          owner: classRef,
          // TODO(grouma) - Fill these in.
          isConst: false,
          isFinal: false,
          isStatic: false,
          id: createId(),
        ),
        value: instance);
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
  Future<List<MapAssociation>> _mapAssociations(
      RemoteObject map, int offset, int count) async {
    // We do this in in awkward way because we want the keys and values, but we
    // can't return things by value or some Dart objects will come back as
    // values that we need to be RemoteObject, e.g. a List of int.
    var expression = '''
      function() {
        var sdkUtils = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk').dart;
        var entries = sdkUtils.dloadRepl(this, "entries");
        entries = sdkUtils.dsendRepl(entries, "toList", []);
        function asKey(entry) {
          return sdkUtils.dloadRepl(entry, "key");
        }
        function asValue(entry) {
          return sdkUtils.dloadRepl(entry, "value");
        }
        return {
          keys: entries.map(asKey),
          values: entries.map(asValue)
        };
      }
    ''';
    var keysAndValues = await inspector.jsCallFunctionOn(map, expression, []);
    var keys = await inspector.loadField(keysAndValues, 'keys');
    var values = await inspector.loadField(keysAndValues, 'values');
    var keysInstance = await instanceFor(keys, offset: offset, count: count);
    var valuesInstance =
        await instanceFor(values, offset: offset, count: count);
    var associations = <MapAssociation>[];
    Map.fromIterables(keysInstance.elements, valuesInstance.elements)
        .forEach((key, value) {
      associations.add(MapAssociation(key: key, value: value));
    });
    return associations;
  }

  /// Create a Map instance with class [classRef] from [remoteObject].
  Future<Instance> _mapInstanceFor(ClassRef classRef, RemoteObject remoteObject,
      List<Property> _, int offset, int count) async {
    // Maps are complicated, do an eval to get keys and values.
    var associations = await _mapAssociations(remoteObject, offset, count);
    var length = (offset == null && count == null)
        ? associations.length
        : (await instanceRefFor(remoteObject)).length;
    return Instance(
        kind: InstanceKind.kMap, id: remoteObject.objectId, classRef: classRef)
      ..length = length
      ..offset = offset
      ..count = (associations.length == length) ? null : associations.length
      ..associations = associations;
  }

  /// Create a List instance of [classRef] from [remoteObject] with the JS
  /// properties [properties].
  Future<Instance> _listInstanceFor(
      ClassRef classRef,
      RemoteObject remoteObject,
      List<Property> properties,
      int offset,
      int count) async {
    var numberOfProperties = _lengthOf(properties);
    var length = (offset == null && count == null)
        ? numberOfProperties
        : (await instanceRefFor(remoteObject)).length;
    var indexed =
        properties.sublist(0, min(count ?? length, numberOfProperties));
    var fields = await Future.wait(indexed
        .map((property) async => await _instanceRefForRemote(property.value)));
    return Instance(
        kind: InstanceKind.kList, id: remoteObject.objectId, classRef: classRef)
      ..length = length
      ..elements = fields
      ..offset = offset
      ..count = (numberOfProperties == length) ? null : numberOfProperties;
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
      const sdk = ${globalLoadStrategy.loadModuleSnippet}("dart_sdk");
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
        : RemoteObject({'value': value, 'type': _chromeType(value)});
    return _instanceRefForRemote(remote);
  }

  /// The Chrome type for a value.
  String _chromeType(Object value) {
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
      return kNullInstanceRef;
    }

    switch (remoteObject.type) {
      case 'string':
        var stringValue = remoteObject.value as String;
        // TODO: Support truncation for long strings.
        // TODO(#777): dartIdFor() will return an ID containing the entire
        // string, even if we're truncating the string value here.
        return InstanceRef(
            id: dartIdFor(remoteObject.value),
            classRef: classRefForString,
            kind: InstanceKind.kString)
          ..valueAsString = stringValue
          ..length = stringValue.length;
      case 'number':
        return _primitiveInstanceRef(InstanceKind.kDouble, remoteObject);
      case 'boolean':
        return _primitiveInstanceRef(InstanceKind.kBool, remoteObject);
      case 'undefined':
        return _primitiveInstanceRef(InstanceKind.kNull, remoteObject);
      case 'object':
        if (remoteObject.objectId == null) {
          return _primitiveInstanceRef(InstanceKind.kNull, remoteObject);
        }
        var metaData = await ClassMetaData.metaDataFor(
            inspector.remoteDebugger, remoteObject, inspector);
        if (metaData == null) return null;
        if (metaData.isSystemList) {
          return InstanceRef(
              kind: InstanceKind.kList,
              id: remoteObject.objectId,
              classRef: metaData.classRef)
            ..length = metaData.length;
        }
        if (metaData.isSystemMap) {
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
        var functionMetaData = await FunctionMetaData.metaDataFor(
            inspector.remoteDebugger, remoteObject);
        return InstanceRef(
            kind: InstanceKind.kClosure,
            id: remoteObject.objectId,
            classRef: classRefForClosure)
          // TODO(grouma) - fill this in properly.
          ..closureFunction = FuncRef(
              name: functionMetaData.name,
              id: createId(),
              // TODO(alanknight): The right ClassRef
              owner: classRefForUnknown,
              isConst: false,
              isStatic: false)
          ..closureContext = (ContextRef(length: 0, id: createId()));
      default:
        // Return null for an unsupported type. This is likely a JS construct.
        return null;
    }
  }
}
