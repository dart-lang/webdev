// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Functions for converting between the different object references we use.
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// A Map representing a RemoteObject for a primitive object.
Map<String, Object> _mapForPrimitive(Object primitive) {
  return {'type': jsTypeOf(primitive), 'value': primitive};
}

/// A Map representing a RemoteObject from an actual RemoteObject.
Map<String, Object> _mapForRemote(RemoteObject remote) {
  return {'type': 'object', 'objectId': remote.objectId};
}

/// The JS type name to use in a RemoteObject reference to [object].
String jsTypeOf(Object object) {
  if (object == null) return 'undefined';
  if (object is String) return 'string';
  if (object is num) return 'num';
  if (object is bool) return 'bool';
  return 'object';
}

/// Convert [argument] to a form usable in WIP evaluation calls.
///
/// The [argument] should be either a RemoteObject or a simple
/// object that can be passed through the protocol directly.
Map<String, Object> mapForObject(Object argument) {
  if (argument is RemoteObject) {
    return argument.objectId == null
        ? _mapForPrimitive(argument.value)
        : _mapForRemote(argument);
  } else {
    return _mapForPrimitive(argument);
  }
}

/// A Chrome RemoteObject from a Dart object Id.
///
/// We expect Dart object Ids to be one of the following forms.
///   * Chrome objectId - e.g. '{"injectedScriptId":1,"id":1}'
///   * Our fabricated string Id - e.g. '#StringInstanceRef#actualString'
///   * Dart fabricated IDs - e.g.  objects/int-8765
/// ##### NOT Library IDs Where are those handled?
///
/// We return either a RemoteObject or a serializable value.
Future<RemoteObject> remoteObjectFor(String dartId) async {
  var data = <String, Object>{};
  if (dartId.startsWith(_prefixForStringIds)) {
    data['type'] = 'string';
    data['value'] = _stringFromDartId(dartId);
  } else if (dartId.startsWith(_prefixForIntIds)) {
    data['type'] = 'number';
    data['value'] = _intFromDartId(dartId);
  } else if (dartId.startsWith(_prefixForBoolIds)) {
    data['type'] = 'boolean';
    data['value'] = dartId.endsWith('true');
  } else if (dartId == _nullId) {
    data['type'] = 'undefined';
    data['value'] = null;
  } else {
    data['type'] = 'object';
    data['objectId'] = dartId;
  }
  return RemoteObject(data);
}

/// A dart object Id appropriate for [argument].
///
/// This will work for simple values, RemoteObject, and Maps 
/// representing RemoteObjects.
String dartIdFor(Object argument) {
  if (argument == null) {
    return '$_nullId';
  }
  if (argument is String) {
    return '$_prefixForStringIds$argument';
  }
  if (argument is int) {
    return '$_prefixForIntIds$argument';
  }
  if (argument is bool) {
    return '$_prefixForBoolIds$argument';
  }
  if (argument is String) {
    return '$_prefixForStringIds$argument';
  }
  if (argument is RemoteObject) {
    return argument.objectId;
  }
  if (argument is Map<String, dynamic>) {
    var id = argument['objectId'] as String;
    if (id == null) {
      throw ArgumentError.value(argument, 'objectId', 'No objectId found');
    }
    return id;
  }
  throw ArgumentError.value(argument, 'objectId', 'No objectId found');
}

/// Given a Dart object Id for a String, return the String.
///
/// If the ID is not for a String, throws ArgumentError. If you don't know what
/// the ID represents, use a more general API like [remoteObjectFor] and if it
/// is a primitive, you can get the value.
String stringFromDartId(String dartId) {
  if (!isStringId(dartId)) {
    throw ArgumentError.value(
        dartId, 'dart object ID', 'Expected a valid ID for a String');
  }
  return _stringFromDartId(dartId);
}

/// Given a Dart object Id for a boolean, return the boolean.
///
/// If the ID is not for a boolean, throws ArgumentError. If you don't know what
/// the ID represents, use a more general API like [remoteObjectFor] and if it
/// is a primitive, you can get the value.
bool boolFromDartId(String dartId) {
  if (!isBoolId(dartId)) {
    throw ArgumentError.value(
        dartId, 'dart object ID', 'Expected a valid ID for a boolean');
  }
  return _boolFromDartId(dartId);
}

/// Given a Dart object Id for an int, return the int.
///
/// If the ID is not for an int, throws ArgumentError. If you don't know what
/// the ID represents, use a more general API like [remoteObjectFor] and if it
/// is a primitive, you can get the value.
int intFromDartId(String dartId) {
  if (!isIntId(dartId)) {
    throw ArgumentError.value(
        dartId, 'dart object ID', 'Expected a valid ID for an int');
  }
  return _intFromDartId(dartId);
}

bool isStringId(String dartId) => dartId.startsWith(_prefixForStringIds);
bool isBoolId(String dartId) => dartId.startsWith(_prefixForBoolIds);
bool isIntId(String dartId) => dartId.startsWith(_prefixForIntIds);
bool isLibraryId(String dartId) => _uriPrefixes.any(dartId.startsWith);

/// Prefixes we use to identify if a Dart ID is a library URI.
const _uriPrefixes = ['dart:', 'package:', 'org-dartlang-app:'];

String _stringFromDartId(String dartIdForString) =>
    dartIdForString.substring(_prefixForStringIds.length);

int _intFromDartId(String dartIdForInt) =>
    int.tryParse(dartIdForInt.substring(_prefixForIntIds.length));

bool _boolFromDartId(String dartId) =>
    dartId.substring(_prefixForIntIds.length) == 'true';

/// Chrome doesn't give us an objectId for a String. So we use the string
/// as its own ID, with a prefix.
///
/// This should not be confused with any
/// other object Ids, as those will be Chrome objectIds, which are
/// opaque, but are JSON serialized objects of the form
/// "{\"injectedScriptId\":1,\"id\":1}".
const _prefixForStringIds = '#StringInstanceRef#';

/// The prefix the Dart VM uses for ints, followed by a string representation of
/// the number.
const _prefixForIntIds = 'objects/int-';

/// The prefix the Dart VM uses for booleans, followed by 'true' or 'false'.
const _prefixForBoolIds = 'objects/bool-';

/// The object id the Dart VM uses for null.
const _nullId = 'objects/null';
