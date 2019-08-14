// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/utilities/objects.dart';

/// Find the visible Dart properties from a JS Scope Chain, coming from the
/// scopeChain attribute of a Chrome CallFrame.
///
/// See
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-CallFrame
///
/// The [scopeList] is a List of maps corresponding to Chrome Scope objects.
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Scope
Future<List<Property>> visibleProperties(
    {List<Map<String, dynamic>> scopeList,
    Debugger debugger,
    String callFrameId}) async {
  // We skip the global and the outer library scope and assume everything before
  // that is a method scope.
  var numberOfMethods = scopeList.length - 2;
  var methodScopes = scopeList
      .sublist(0, numberOfMethods)
      .map((x) => MethodScope(
          objectId: x['object']['objectId'] as String,
          callFrameId: callFrameId,
          debugger: debugger))
      .toList();
  for (var scope in methodScopes) {
    await scope.fetchProperties();
  }
  var properties = [for (var scope in methodScopes) ...scope.properties];
  return properties;
}

class MethodScope {
  String objectId;
  String callFrameId;

  List<Property> properties;

  Debugger debugger;

  Property self;

  MethodScope({this.objectId, this.callFrameId, this.debugger});

  /// Retrieve the properties for this scope, including finding a `this` binding
  /// if available, even if it's not included in the original Chrome scope
  /// object.
  Future<void> fetchProperties() async {
    properties = await debugger.getProperties(objectId);
    self = properties.firstWhere((x) => x.name == 'this', orElse: () => null);
    self ??= await findMissingThis();
  }

  /// Fill in the 'this' scope if it wasn't in the original scope.
  ///
  /// If we were not given a 'this' value in the Chrome scopes that might mean
  /// we're in a nested closure, or we might be a top-level function.
  /// Construct a 'this'. If it turns out to be null/undefined, make it empty.
  /// If it just duplicates the containing library, ignore it. Otherwise insert
  /// it into the scope where it will get expanded normally.
  Future<Property> findMissingThis() async {
    if (self != null) return self;
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
        await debugger.evaluateJsOnCallFrame(callFrameId, findCurrent);

    if (actualThis.type != 'undefined') {
      /// Construct a property for `this`.
      self = Property({'name': 'this', 'value': actualThis});
      properties.add(self);
    }
    return self;
  }
}
