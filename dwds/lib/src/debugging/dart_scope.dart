// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../loaders/strategy.dart';
import '../utilities/objects.dart';
import 'debugger.dart';

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
  var scopes = await _filterScopes(scopeList, debugger);
  if (scopes.isEmpty) return [];
  var propertyLists = scopes
      .map((scope) async =>
          await debugger.getProperties(scope['object']['objectId'] as String))
      .toList();
  var allProperties = [for (var list in propertyLists) ...await list];
  // We should never see a raw JS class. The only case where this happens is a
  // Dart generic function, where the type arguments get passed in as
  // parameters. Hide those.
  // TODO(#786) Handle these correctly rather than just suppressing them.
  allProperties.removeWhere((each) =>
      (each.value.type == 'function' &&
          each.value.description.startsWith('class ')) ||
      (each.value.type == 'object' &&
          each.value.description == 'dart.LegacyType.new'));
  var existingThis =
      allProperties.firstWhere((x) => x.name == 'this', orElse: () => null);
  if (existingThis == null) {
    var syntheticThis = await _findMissingThis(callFrameId, debugger);
    if (syntheticThis != null) {
      allProperties.add(syntheticThis);
    }
  }
  return allProperties;
}

/// Filters the provided scope chain into those that are pertinent for Dart
/// debugging.
Future<List<Map<String, dynamic>>> _filterScopes(
    List<Map<String, dynamic>> scopeList, Debugger debugger) async {
  var foundDartSdk = false;
  var result = <Map<String, dynamic>>[];
  // Iterate through the outermost scope to the inner most scope.
  for (var scope in scopeList.reversed) {
    var properties =
        await debugger.getProperties(scope['object']['objectId'] as String);
    if (!foundDartSdk) {
      var propertyNames = properties.map((element) => element.name).toSet();
      // TODO(sdk/issues/40774) - This appears brittle.
      if (propertyNames.containsAll(['core', 'dart'])) foundDartSdk = true;
    } else {
      // Scopes after the Dart SDK is defined contain application logic.
      result.add(scope);
    }
  }
  return result;
}

/// Find the `this` in scope if it wasn't in the provided data from Chrome.
///
/// If we were not given a `this` value in the Chrome scopes that might mean
/// we're in a nested closure, or we might be a top-level function. Find it by evaluating
/// code in the JS frame. If it's null/undefined or is a Dart library scope, then
/// return null. Otherwise make a property for `this` and return it.
Future<Property> _findMissingThis(String callFrameId, Debugger debugger) async {
  // If 'this' is a library return null, otherwise
  // return 'this'.
  final findCurrent = '''
        (function (THIS) {
           if (THIS === window) { return null; }
           ${globalLoadStrategy.loadLibrariesSnippet}
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
