// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/instance.dart';
import 'package:dwds/src/utilities/objects.dart';

/// A JS Scope Chain, representing the scopeChain attribute of a Chrome
/// CallFrame.
///
/// See
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-CallFrame
///
/// We create this mostly to enable converting it into a corresponding DartScopeChain which
/// has variable visibility determined by Dart semantics.
class JsScopeChain {
  Debugger debugger; // ####

  /// All of the visible method (i.e. not global or Dart library) scopes.
  List<MethodScope> methodScopes;

  /// The ID of the call frame for which these are the visible scopes.
  String callFrameId;

  JsScopeChain(this.methodScopes, this.debugger, this.callFrameId);

  /// The [scopeList] is a List of maps corresponding to Chrome Scope objects.
  ///
  /// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Scope
  static Future<JsScopeChain> fromJs(
      {List<Map<String, dynamic>> scopeList,
      Debugger debugger,
      String callFrameId}) async {
    // We skip the global and the outer library scope and assume everything before
    // that is a method scope.
    var numberOfMethods = scopeList.length - 2;
    var futureScopes = scopeList
        .sublist(0, numberOfMethods)
        .map((x) async => await MethodScope.create(
            name: (x['name'] ?? 'unnamed') as String,
            objectId: x['object']['objectId'] as String,
            debugger: debugger))
        .toList();
    var methodScopes = await Future.wait(futureScopes);
    var scopeChain = JsScopeChain(methodScopes, debugger, callFrameId);
    // Now we can set the containing scopeChain for the created scopes. We
    // couldn't do this earlier because we hadn't created it yet.
    for (var scope in methodScopes) {
      scope.chain = scopeChain;
    }
    return scopeChain;
  }

  /// Convert to a scope chain that represents the method and `this` scope
  /// variables visible under Dart semantics.
  Future<List<Scope>> toDartScopeChain() async {
    methodScopes = methodScopes
        .map((scope) => scope.toDartScope())
        .cast<MethodScope>()
        .toList();
    // Add a scope for [this] if present, even if it wasn't in Chrome.
    var jsThis = await thisScope();
    return [...methodScopes, jsThis.toDartScope()];
  }

  /// The scope corresponding to `this`.
  Future<ThisScope> thisScope() async {
    // We may have nested closures. Return the scope of [this] for the first
    // one that has a valid [this], to avoid including its values more than
    // once.
    for (var scope in methodScopes) {
      var thisScope = await scope._addThisIfMissing();
      if (thisScope.isNotEmpty()) return thisScope;
    }
    // We didn't find a non-empty [ThisScope]. Return one of the empty ones.
    return methodScopes[0].thisScope;
  }
}

/// Variables in scope from a particular call frame.
class Scope {
  /// The name of this kind of scope. Comes from the JS [chain] and is only used
  /// for debugging purposes.
  ///
  /// It may contain the name of the method, or may just say it's a closure, or
  /// global.
  String name;

  /// All the visible variables, with their names.
  List<Property> properties;

  /// The containing scope chain.
  JsScopeChain chain;

  Debugger get _debugger => chain.debugger;

  Scope(this.name, this.properties, this.chain);

  /// Look up a property by name.
  Property propertyNamed(String propertyName) {
    return properties.firstWhere((prop) => prop.name == propertyName,
        orElse: () => null);
  }

  /// All the properties whose names are not symbols.
  List<Property> propertiesWithoutSymbols() {
    // These are remote objects, but we can tell which ones are symbols
    // without a round-trip because their string name in the remote object
    // starts with 'Symbol('
    return properties.where((property) => !propertyIsSymbol(property)).toList();
  }

  /// Determine if a property is a symbol without a round-trip by looking at
  /// its name.
  bool propertyIsSymbol(Property property) =>
      property.name.startsWith('Symbol(');

  /// Convert a symbol name to its non-symbol form.
  String nonSymbolName(String name) =>
      name.substring('Symbol('.length, name.length - 1);

  /// Returns a new scope modified to reflect Dart visibility for a scope of
  /// this type.
  // ignore: avoid_returning_this
  Scope toDartScope() => this;

  /// Get all the internal properties of [property], because they should be
  /// visible in Dart scope.
  ///
  /// This can apply to either `this` or to a library.
  Future<List<Property>> expand(Property property) async {
    if (property == null ||
        (property.name).startsWith('_') ||
        property.value.objectId == null) {
      return [];
    }
    return await _debugger.getProperties(property.value.objectId);
  }
}

class MethodScope extends Scope {
  /// The scope corresponding to the `this` of the method.
  ///
  /// If there is no `this`, e.g. if it's a function, there will
  /// still be an empty scope.
  ThisScope _thisScope;

  /// The property for `this`.
  ///
  /// Will be null if there is no `this` for this method/function.
  Property self;

  MethodScope._(String name, List<Property> properties, JsScopeChain chain)
      : super(name, properties, chain) {
    self = properties.firstWhere((x) => x.name == 'this', orElse: () => null);
  }

  /// A static creation method, which is the normal path because we want to do
  /// async operations.
  ///
  /// Either [chain] or [debugger] may be omitted. The [debugger] parameter is
  /// for the case of creating a MethodScope when we don't yet have the
  /// containing [JsScopeChain].
  static Future<MethodScope> create(
      {String name,
      String objectId,
      JsScopeChain chain,
      Debugger debugger}) async {
    var properties =
        await (chain?.debugger ?? debugger).getProperties(objectId);
    return MethodScope._(name, properties, chain);
  }

  @override
  MethodScope toDartScope() => this;

  /// Return the scope of `this` for the method.
  ///
  /// If called after _addThisIfMissing, this should always have a value, though
  /// it may be an artificial empty scope.
  ThisScope get thisScope => _thisScope;

  /// Fill in the 'this' scope if it wasn't in the original scope.
  ///
  /// If we were not given a 'this' value in the Chrome scopes that might mean
  /// we're in a nested closure, or we might be a top-level function.
  /// Construct a 'this'. If it turns out to be null/undefined, make it empty.
  /// If it just duplicates the containing library, ignore it. Otherwise insert
  /// it into the scope where it will get expanded normally.
  Future<ThisScope> _addThisIfMissing() async {
    if (_thisScope != null) return _thisScope;
    // If 'this' is a library return null, otherwise
    // return 'this'.
    const findCurrent = '''
        (function (THIS) { 
           if (THIS === window) { return null; }
           let dart = require('dart_sdk').dart
           let libs = dart.getLibraries().map(dart.getLibrary);
           for (let lib of libs) {
             if (lib === THIS) {
                return null;
            }
            } return THIS; })(this)''';

    var actualThis =
        await _debugger.evaluateJsOnCallFrame(chain.callFrameId, findCurrent);

    if (actualThis.type != 'undefined') {
      /// Construct a property for `this`.
      self = Property({'name': 'this', 'value': actualThis});
      properties.add(self);
      _thisScope = ThisScope('this', await expand(self), chain);
    } else {
      _thisScope = ThisScope('empty', [], chain);
    }
    return _thisScope;
  }
}

class ThisScope extends Scope {
  ThisScope(String name, List<Property> properties, JsScopeChain chain)
      : super(name, properties, chain);

  /// Returns a scope which includes fields of the current object, which are
  /// visible without a prefix in Dart.
  @override
  ThisScope toDartScope() {
    // Private instance fields have a name that's a  symbol. Strip it down to
    // just the private name.
    var newProperties = <Property>[];
    for (var property in properties) {
      if (propertyIsSymbol(property)) {
        newProperties.add(Property({
          'name': nonSymbolName(property.name),
          'value': property.rawValue
        }));
      } else {
        newProperties.add(property);
      }
    }
    var newScope = ThisScope(name, newProperties, chain);

    /// Remove all remaining symbols and other things we don't want visible.
    return newScope.withoutSymbols().withoutIgnored();
  }

  /// Is this scope non-empty, i.e. there is no 'this'
  bool isEmpty() {
    return properties.isEmpty;
  }

  /// Is this scope non-empty, i.e. there is a valid 'this'
  bool isNotEmpty() {
    return !isEmpty();
  }

  /// Return a scope based on this one without properties whose names are
  /// symbols.
  ThisScope withoutSymbols() {
    return ThisScope(name, propertiesWithoutSymbols(), chain);
  }

  /// Is the property named [property] one that we should ignore.
  bool isIgnoredProperty(Property property) {
    // TODO(alanknight): Make this more rigorous, especially the
    // _is_<className> check.
    // TODO(alanknight): Will this handle private superclass fields. Do we
    // see those symbols?  They might be in a separate package, but we may
    // want to include them and assume that dloadRepl will handle them.
    return property.name.startsWith('_is_') ||
        fieldNamesToIgnore.contains(property.name);
  }

  /// Return a scope based on this one but without names that we don't want to
  /// show up.
  ///
  /// These are typically either from JS, or additional methods that DDC adds,
  /// e.g. the _is_ tests for classes.
  ThisScope withoutIgnored() {
    return ThisScope(
        name, properties.where((p) => !isIgnoredProperty(p)).toList(), chain);
  }
}
