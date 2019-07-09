// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

/// A library for WebKit mirror objects and support code. These probably should
/// get migrated into webkit_inspection_protocol over time.

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// Represents a property of an object.
class Property {
  final Map<String, dynamic> _map;

  Property(this._map);

  /// The remote object value in unwrapped form.
  ///
  /// Useful for getting access to properties of particular types of
  /// RemoteObject.
  Map<String, dynamic> get rawValue => _map['value'] as Map<String, dynamic>;

  /// Remote object value in case of primitive values or JSON values (if it was
  /// requested). (optional)
  RemoteObject get value => RemoteObject(rawValue);

  /// The name of the property
  String get name => _map['name'] as String;

  @override
  String toString() => '$name $value';
}
