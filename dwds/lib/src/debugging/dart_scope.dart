// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/utilities/objects.dart';

/// Find the visible Dart properties from a JS Scope Chain, coming from the
/// scopeChain attribute of a Chrome CallFrame corresponding to [callFrameId].
///
/// See
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-CallFrame
///
/// The [scopeList] is a List of Maps corresponding to Chrome Scope objects.
/// https://chromedevtools.github.io/devtools-protocol/tot/Debugger#type-Scope
Future<List<Property>> visibleProperties(
    {List<Map<String, dynamic>> scopeList,
    Debugger debugger,
    String callFrameId}) async {
  // We skip the global and the outer library scope and assume everything before
  // that is a method scope.
  var numberOfMethods = scopeList.length - 2;
  var propertyLists = scopeList
      .sublist(0, numberOfMethods)
      .map((x) async => await _propertiesForScope(
          scopeId: x['object']['objectId'] as String,
          callFrameId: callFrameId,
          debugger: debugger))
      .toList();
  var properties = [for (var list in propertyLists) ...await list];
  return properties;
}

/// The properties for this scope, including a `this` binding if available, even
/// if it's not included in the original Chrome scope object.
Future<List<Property>> _propertiesForScope(
    {String scopeId, String callFrameId, Debugger debugger}) async {
  var properties = await debugger.getProperties(scopeId);
  var self = properties.firstWhere((x) => x.name == 'this', orElse: () => null);
  if (self == null) {
    var syntheticSelf = await _findMissingThis(callFrameId, debugger);
    if (syntheticSelf != null) {
      properties.add(syntheticSelf);
    }
  }
  return properties;
}

/// Fill in the `this` scope if it wasn't in the original scope.
///
/// If we were not given a `this` value in the Chrome scopes that might mean
/// we're in a nested closure, or we might be a top-level function. Construct a
/// 'this'. If it turns out to be null/undefined, or it is a Dart library scope,
/// make it empty. Otherwise insert it into the list of properties.
Future<Property> _findMissingThis(String callFrameId, Debugger debugger) async {
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
  return (actualThis.type == 'undefined')
      ? null
      : Property({'name': 'this', 'value': actualThis});
}
