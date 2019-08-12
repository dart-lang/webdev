// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/utilities/objects.dart';

class JsScope {
  // from the raw thing.  list of string name, RemoteObjectProperty properties

}

class JsScopeChain {
  static Debugger debugger;

  List<Scope> scopes;
  String libraryName;
  int numberOfMethods;
  List<MethodScope> methodScopes;
  LibraryScope libraryScope;
  String callFrameId;

  // JsScopeChain(this.scopes, this.libraryName, Debugger theDebugger) {
  //   // ignore: prefer_initializing_formals
  //   JsScopeChain.debugger = theDebugger;
  //   scopes = [];
  //   numberOfMethods = scopeList.length - 2;
  //   methodScopes = scopes.take(numberOfMethods).toList()
  //   var futureScopes = scopeList
  //       .take(numberOfMethods)
  //       .map((scope) => MethodScope.fromJs(scope))
  //       .toList();
  //       methodScopes = await Future.wait(futureScopes);
  //   libraryScope = LibraryScope.fromJs(scopeList[scopeList.length - 2]);
  //   dartThisScope = null;
  // }

  JsScopeChain(
      this.methodScopes, this.libraryScope, this.libraryName, this.callFrameId);

  /// We expect the [scopeList] to be a List of maps corresponding to Chrome Scope objects.
  ///
  /// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Scope
  static Future<JsScopeChain> fromJs(List<Map<String, dynamic>> scopeList,
      String libraryName, Debugger theDebugger, String callFrameId) async {
    JsScopeChain.debugger = theDebugger;
    var numberOfMethods = scopeList.length - 2;
    var futureScopes = scopeList.take(numberOfMethods).toList().map((x) async =>
        await MethodScope.fromId((x['name'] ?? 'unnamed') as String,
            x['object']['objectId'] as String, null)).toList();
    var methodScopes = await Future.wait(futureScopes);
    var library = scopeList[numberOfMethods];
    var libraryScope = await LibraryScope.fromId(
        (library['name'] ?? 'unknown library') as String,
        library['object']['objectId'] as String,
        libraryName,
        null);
    var result =
        JsScopeChain(methodScopes, libraryScope, libraryName, callFrameId);
    for (var scope in methodScopes) {
      scope.context = result;
    }
    libraryScope.context = result;
    return result;
  }

  /// Convert to a scope chain that represents the variables visible under
  /// Dart semantics.
  Future<DartScopeChain> toDartScopeChain() async {
    // In the scope of the surrounding libraries, most of the variables
    // aren't visible to Dart. We have objects for Dart libraries, but we
    // need to promote their variables to make them visible. We find those
    // as the remote properties whose description is Object or Proxy. For
    // code completion we want to expand those. For compilation visibility
    // we ignore them, as the compiler will reference them directly.
    // TODO(alanknight): Should we expand all libraries? Skip dart:core?
    // Should libraries with a $ suffix, (e.g. fixnum) be expanded?

    // Method scope.
    methodScopes = methodScopes
        .map((scope) => scope.toDartScope())
        .cast<MethodScope>()
        .toList();

    // Add a scope for [this] if present.
    var dartThisScope = (await thisScope(libraryName)).toDartScope();

    // TODO(alanknight): Is there always an active library? Can we rely on
    // having bailed out well befo_allScopesre this if we're in a JS scope.
    var libraries = await libraryScope.expanded();
    return DartScopeChain(methodScopes, dartThisScope, libraries);
  }

  /// The scope corresponding to `this`.
  Future<ThisScope> thisScope(String libraryName) async {
    // We may have nested closures. Return the scope of [this] for the first
    // one that has a valid [this], to avoid including its values more than
    // once.
    for (var scope in methodScopes) {
      await scope._addThisIfMissing(libraryName);
      var thisScope = await scope.thisScope(libraryName);
      if (thisScope.isNotEmpty()) return thisScope;
    }
    // We didn't find a non-empty [_ThisScope]. Return the first (empty) one.
    return methodScopes[0].thisScope(libraryName);
  }
}

class DartScopeChain {
  List<MethodScope> methodScopes;
  ThisScope thisScope;
  List<LibraryScope> libraryScopes;

  DartScopeChain(this.methodScopes, this.thisScope, this.libraryScopes);

  List<Scope> allScopes() => [...methodScopes, thisScope];
}

class Scope {
  String name;
  List<Property> properties;
  JsScopeChain context;
  Scope(Scope scope, String name, List<Property> properties, this.context) {
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
    // #### not sure this is a RemoteObject so much as a BoundVariable or Property already????
    if (property == null || (property.name).startsWith('_')) {
      return [];
    }
    return await JsScopeChain.debugger.getProperties(property.value.objectId);
  }
}

/// ##### We may need to distinguish between the equivalent of RemoteObjectProperty and our outgoing property
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
      Scope scope, String name, List<Property> properties, JsScopeChain context)
      : super(scope, name, properties, context) {
    self = properties.firstWhere((x) => x.name == 'this', orElse: () => null);
  }

  static Future<MethodScope> fromId(
      String name, String objectId, JsScopeChain context) async {
    var properties = await JsScopeChain.debugger.getProperties(objectId);
    return MethodScope(null, name, properties, context);
  }

  static Future<MethodScope> fromJs(
      Map<String, dynamic> jsScope, JsScopeChain context) async {
    var properties = await JsScopeChain.debugger
        .getProperties(jsScope['object']['objectId'] as String);
    return MethodScope(null, jsScope['name'] as String, properties, context);
  }

  Future<ThisScope> thisScope(String libraryName) async {
    if (_thisScope != null) return _thisScope;
    var properties = (await expand(self)) ?? [];
    return _thisScope = ThisScope(null, 'this', properties, context);
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
  Future<void> _addThisIfMissing(String libraryName) async {
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

    var actualThis = await JsScopeChain.debugger.inspector
        .evaluateJsOnCallFrame(context.callFrameId, findCurrent);

    // Guard against a null result, particularly in tests
    // actualThis = actualThis?.object;
    if (actualThis.type != 'undefined') {
      // Construct something that looks like a RemoteObjectProperty
      self = Property({'name': 'this', 'value': actualThis});
      properties.add(self);
    } else {
      _thisScope = ThisScope(null, 'empty', [], context);
    }
  }
}

class ThisScope extends Scope {
  ThisScope(
      Scope scope, String name, List<Property> properties, JsScopeChain context)
      : super(scope, name, properties, context);

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
    var newScope = ThisScope(null, name, newProperties, context);

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
    return ThisScope(this, null, propertiesWithoutSymbols(), context);
  }

  /// Is the property named [property] one that we should ignore.
  bool isIgnoredProperty(Property property) {
    return property.name.startsWith('_is_') ||
        _namesToIgnore.contains(property.name);
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
        properties.where((p) => !isIgnoredProperty(p)).toList(), context);
  }
}

class LibraryScope extends Scope {
  String activeLibraryName;

  static Future<LibraryScope> fromId(String name, String objectId,
      String libraryName, JsScopeChain context) async {
    var properties = await JsScopeChain.debugger.getProperties(objectId);
    return LibraryScope(null, name, properties, libraryName, context);
  }

  LibraryScope(Scope scope, String name, List<Property> properties,
      this.activeLibraryName, JsScopeChain context)
      : super(scope, name, properties, context);

  /// Does this property look like it contains another library.
  bool _isLibrary(Property property) {
    if (property.value == null) return false;
    if (property.name == activeLibraryName) return false;
    return property.value.description == 'Object' ||
        property.value.description == 'Proxy';
  }

  /// The property representing the active library.
  Property activeLibrary() {
    return propertyNamed(activeLibraryName);
  }

  /// Expand this into a list of the visible library scopes.
  Future<List<LibraryScope>> expanded() async {
    var lib = activeLibrary();
    var allLibraries = <LibraryScope>[];
    if (lib != null) {
      var expanded = await _expandThisLibrary();
      allLibraries.add(expanded);
    }
    return [...allLibraries, ...await _expandOthers()];
  }

  Future<LibraryScope> _expandThisLibrary() async {
    var library = activeLibrary();
    if (library == null) return null;
    var expanded = await expand(library);
    return LibraryScope(null, name, expanded, activeLibraryName, context);
  }

  Future<List<LibraryScope>> _expandOthers() async {
    var otherLibraries = properties.where(_isLibrary);
    var newScopes = <LibraryScope>[];
    for (var library in otherLibraries) {
      var libraryProperties = await expand(library);
      var libraryVariables = LibraryScope(
          null, 'library', libraryProperties, library.name, context);
      newScopes.add(libraryVariables);
    }
    return newScopes;
  }
}

/// JS names that we don't want to show up in autocomplete or to pass to
/// evaluation.
const Set<String> _namesToIgnore = {
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
