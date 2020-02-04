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

/// Represents Scope object from chrome devtools protocol
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Scope
class Scope {
  RemoteObject _object;
  final Map<String, dynamic> _map;

  Scope(this._map) {
    _object = RemoteObject(_rawObject);
  }

  Map<String, dynamic> get _rawObject => _map['object'] as Map<String, dynamic>;

  RemoteObject get object => _object;
  String get type => _map['type'] as String;
  String get name => _map['name'] as String;

  @override
  String toString() => 'JsScope: type: $type, name: $name, object: $object';
}

/// Represents ScopeChain object from chrome devtools protocol, used in
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-CallFrame
class ScopeChain {
  final List<dynamic> _chain;
  Iterable<Scope> _scopes;

  ScopeChain(this._chain) {
    _scopes =
        _chain.reversed.map((elem) => Scope(elem as Map<String, dynamic>));
  }

  Iterable<Scope> get scopes => _scopes;

  Scope get libraryScope => _scopes.first;
  Scope get mainScope => _scopes.skip(1).first;
  Iterable<Scope> get innerScopes => _scopes.skip(2);

  @override
  String toString() => 'ScopeChain: $scopes';
}

/// Represents Location object from chrome devtools protocol
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Location
class Location {
  final Map<String, dynamic> _map;

  Location(this._map);

  String get scriptId => _map['scriptId'] as String;
  int get lineNumber => _map['lineNumber'] as int;
  int get columnNumber => _map['columnNumber'] as int;

  @override
  String toString() =>
      'Location: scriptId: $scriptId, line: $lineNumber, column: $columnNumber';
}

/// Represents CallFrame object from chrome devtools protocol
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-CallFrame
class CallFrame {
  final Map<String, dynamic> _map;
  Location _location;
  ScopeChain _scopeChain;

  CallFrame(this._map) {
    _location = Location(_rawLocation);
    _scopeChain = ScopeChain(_rawScopeChain);
  }

  Map<String, dynamic> get _rawLocation =>
      _map['location'] as Map<String, dynamic>;
  List<dynamic> get _rawScopeChain => _map['scopeChain'] as List<dynamic>;

  Location get location => _location;
  String get functionName => _map['functionName'] as String ?? '';
  ScopeChain get scopeChain => _scopeChain;

  @override
  String toString() =>
      'CallFrame: location: $location, functionName: $functionName, scopeChain: $scopeChain';
}
