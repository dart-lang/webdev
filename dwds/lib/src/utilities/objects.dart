// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

/// A library for WebKit mirror objects and support code. These probably should
/// get migrated into webkit_inspection_protocol over time.

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// Represents a property of an object.
class Property {
  final Map<String, dynamic> _map;
  RemoteObject _remoteObjectValue;

  Property(this._map);

  /// The remote object value in unwrapped form.
  ///
  /// Useful for getting access to properties of particular types of
  /// RemoteObject.
  Object get rawValue => _map == null ? null : _map['value'];

  /// Remote object value in case of primitive values or JSON values (if it was
  /// requested). (optional)
  RemoteObject get value {
    if (_remoteObjectValue != null) return _remoteObjectValue;
    if (rawValue == null) return null;
    var val = _map['value'];
    if (val is RemoteObject) {
      _remoteObjectValue = val;
    } else {
      _remoteObjectValue = RemoteObject(val as Map<String, dynamic>);
    }
    return _remoteObjectValue;
  }

  /// The name of the property
  String get name {
    const prefix = 'Symbol(';
    var nonSymbol = (rawName.startsWith(prefix))
        ? rawName.substring(prefix.length, rawName.length - 1)
        : rawName;
    return nonSymbol.split('.').last;
  }

  /// The raw name of the property in JS.
  ///
  /// Will be of the form 'Symbol(_actualName)' for private fields.
  String get rawName => _map['name'] as String;

  @override
  String toString() => '$name $value';
}
