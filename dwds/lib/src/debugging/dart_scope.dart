// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/utilities/shared.dart';

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
  // We skip the global and the outer library scope and assume everything before
  // that is a method scope.
  var numberOfMethods = scopeList.length - 2;
  if (numberOfMethods <= 0) return [];
  var methodScopes = scopeList.sublist(0, numberOfMethods);
  var propertyLists = methodScopes
      .map((scope) async =>
          await debugger.getProperties(scope['object']['objectId'] as String))
      .toList();
  var allProperties = [for (var list in propertyLists) ...await list];
  // We should never see a raw JS class. The only case where this happens is a
  // Dart generic function, where the type arguments get passed in as
  // parameters. Hide those.
  // TODO(#786) Handle these correctly rather than just suppressing them.
  allProperties.removeWhere((each) =>
      each.value.type == 'function' &&
      each.value.description.startsWith('class '));
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
           $getLibraries
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
