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
  static Debugger debugger; // ####

  /// All of the visible method (i.e. not global or Dart library) scopes.
  List<MethodScope> methodScopes;

  /// The ID of the call frame for which these are the visible scopes.
  String callFrameId;

  JsScopeChain(this.methodScopes, this.callFrameId);

  /// The [scopeList] is a List of maps corresponding to Chrome Scope objects.
  ///
  /// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Scope
  static Future<JsScopeChain> fromJs(
      {List<Map<String, dynamic>> scopeList,
      Debugger debugger,
      String callFrameId}) async {
    JsScopeChain.debugger = debugger;
    // We skip the global and the outer library scope and assume everything before
    // that is a method scope.
    var numberOfMethods = scopeList.length - 2;
    var futureScopes = scopeList
        .sublist(0, numberOfMethods)
        .map((x) async => await MethodScope.create(
            name: (x['name'] ?? 'unnamed') as String,
            objectId: x['object']['objectId'] as String,
            chain: null))
        .toList();
    var methodScopes = await Future.wait(futureScopes);
    var scopeChain = JsScopeChain(methodScopes, callFrameId);
    // Now we can set the containing scopeChain for the created scopes. We
    // couldn't do this earlier because we hadn't created it yet.
    for (var scope in methodScopes) {
      scope.chain = scopeChain;
    }
    return scopeChain;
  }

  /// Convert to a scope chain that represents the variables visible under
  /// Dart semantics.
  ///
  /// Note that this does not include library variables at the moment.
  Future<DartScopeChain> toDartScopeChain() async {
    methodScopes = methodScopes
        .map((scope) => scope.toDartScope())
        .cast<MethodScope>()
        .toList();
    // Add a scope for [this] if present, even if it wasn't in v8.
    var dartThisScope = (await thisScope()).toDartScope();
    return DartScopeChain(methodScopes, dartThisScope);
  }

  /// The scope corresponding to `this`.
  Future<ThisScope> thisScope() async {
    // We may have nested closures. Return the scope of [this] for the first
    // one that has a valid [this], to avoid including its values more than
    // once.
    for (var scope in methodScopes) {
      await scope._addThisIfMissing();
      var thisScope = await scope.thisScope();
      if (thisScope.isNotEmpty()) return thisScope;
    }
    // We didn't find a non-empty [ThisScope]. Return one of the empty ones.
    return methodScopes[0].thisScope();
  }
}

class DartScopeChain {
  List<MethodScope> methodScopes;
  ThisScope thisScope;

  DartScopeChain(this.methodScopes, this.thisScope);

  List<Scope> allScopes() => [...methodScopes, thisScope];
}

class Scope {
  String name;
  List<Property> properties;
  JsScopeChain chain;
  Scope(Scope scope, String name, List<Property> properties, this.chain) {
    this.name = name ?? scope.name;
    this.properties = properties ?? scope.properties;
  }

  Property propertyNamed(propertyName) {
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

  /// Returns a new scope modified to reflect Dart visibility for a scope of
  /// this type.
  // ignore: avoid_returning_this
  Scope toDartScope() => this;

  /// Get all the internal properties of the object, because they should be
  /// visible in Dart scope.
  ///
  /// The [property] represents either a library or the current 'this'.
  Future<List<Property>> expand(Property property) async {
    if (property == null ||
        (property.name).startsWith('_') ||
        property.value.objectId == null) {
      return [];
    }
    return await JsScopeChain.debugger.getProperties(property.value.objectId);
  }
}

class MethodScope extends Scope {
  ThisScope _thisScope;
  Property self;

  /// @param {!Dart.Scope || Object} scope. Either one of our scopes or one of
  ///     the anonymous objects that are returned from the devtools scopeChain
  ///     calls.
  /// @param {string} name. Comes from the Devtools scopes. We don't use it,
  ///     but it's useful for debugging.
  /// @param {!List<SDK.RemoteObjectProperty || Object>} properties. The
  ///     properties in this particular scope
  /// @param {string} aliasForThis. The name to use to replace the reserved
  /// word 'this' in parameter lists.
  MethodScope(
      Scope scope, String name, List<Property> properties, JsScopeChain chain)
      : super(scope, name, properties, chain) {
    self = properties.firstWhere((x) => x.name == 'this', orElse: () => null);
  }

  /// A static creation method, which is the normal path because we want to do
  /// async operations.
  static Future<MethodScope> create(
      {String name, String objectId, JsScopeChain chain}) async {
    var properties = await JsScopeChain.debugger.getProperties(objectId);
    return MethodScope(null, name, properties, chain);
  }

  static Future<MethodScope> fromJs(
      Map<String, dynamic> jsScope, JsScopeChain chain) async {
    var properties = await JsScopeChain.debugger
        .getProperties(jsScope['object']['objectId'] as String);
    return MethodScope(null, jsScope['name'] as String, properties, chain);
  }

  @override
  MethodScope toDartScope() => this;

  Future<ThisScope> thisScope() async {
    if (_thisScope != null) return _thisScope;
    var properties = (await expand(self)) ?? [];
    return _thisScope = ThisScope(null, 'this', properties, chain);
  }

  /// Fill in the 'this' scope if it wasn't in the original call.
  ///
  /// If we were not given a 'this' value in the devtools scopes that might mean
  /// we're in a nested closure, or we might be a top-level function.
  /// Construct a 'this'. If it turns out to be null/undefined, make it empty.
  /// If it just duplicates the containing library, ignore it. Otherwise insert
  /// it into the scope where it will get expanded normally.
  ///
  /// @param {string} libraryName. Used when we have to find a 'this' which wasn't
  ///     in the original scopes, but we want to avoid just duplicating the library.
  /// @return {void}  Modifies this.self and this._thisScope
  Future<void> _addThisIfMissing() async {
    if (_thisScope != null || self != null) return;
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

    var actualThis = await JsScopeChain.debugger
        .evaluateJsOnCallFrame(chain.callFrameId, findCurrent);

    // Guard against a null result, particularly in tests
    // actualThis = actualThis?.object;
    if (actualThis.type != 'undefined') {
      // Construct something that looks like a RemoteObjectProperty
      self = Property({'name': 'this', 'value': actualThis});
      properties.add(self);
    } else {
      _thisScope = ThisScope(null, 'empty', [], chain);
    }
  }
}

class ThisScope extends Scope {
  ThisScope(
      Scope scope, String name, List<Property> properties, JsScopeChain chain)
      : super(scope, name, properties, chain);

  /// Returns a scope which includes fields of the current object, which are
  /// visible without a prefix in Dart.
  @override
  ThisScope toDartScope() {
    // Private instance fields have a name that's a symbol. Strip it down to
    // just the private name.
    var newProperties = <Property>[];
    for (var property in properties) {
      if (property.name.startsWith('Symbol(_')) {
        newProperties.add(Property({
          'name': property.name
              .substring('Symbol('.length, property.name.length - 1),
          'value': property.rawValue
        }));
      } else {
        newProperties.add(property);
      }
    }
    var newScope = ThisScope(null, name, newProperties, chain);

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
    return ThisScope(this, null, propertiesWithoutSymbols(), chain);
  }

  /// Is the property named [property] one that we should ignore.
  bool isIgnoredProperty(Property property) {
    return property.name.startsWith('_is_') ||
        fieldNamesToIgnore.contains(property.name);
  }

  /// Return a scope based on this one but without names that we don't want to
  /// show up.
  ///
  /// These are typically either from JS, or additional methods that DDC adds,
  /// e.g. the _is_ tests for classes.
  ///
  /// @return {Dart._ThisScope}
  ThisScope withoutIgnored() {
    // TODO(alanknight): Make this more rigorous, especially the
    // _is_<className> check.
    // TODO(alanknight): Will this handle private superclass fields. Do we
    // see those symbols?  They might be in a separate package, but we may
    // want to include them and assume that dloadRepl will handle them.
    return ThisScope(this, null,
        properties.where((p) => !isIgnoredProperty(p)).toList(), chain);
  }
}
