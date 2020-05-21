// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../utilities/objects.dart';
import 'debugger.dart';

/// Find the visible Dart properties from a JS Scope Chain, coming from the
/// scopeChain attribute of a Chrome CallFrame corresponding to [frame].
///
/// See chromedevtools.github.io/devtools-protocol/tot/Debugger#type-CallFrame.
Future<List<Property>> visibleProperties({
  Debugger debugger,
  WipCallFrame frame,
}) async {
  var allProperties = <Property>[];

  if (frame.thisObject != null && frame.thisObject.type != 'undefined') {
    allProperties.add(
      Property({
        'name': 'this',
        'value': frame.thisObject,
      }),
    );
  }

  // TODO: Try and populate all the property info for the scopes in one backend
  // call. Along with some other optimizations (caching classRef lookups), we'd
  // end up averaging one backend call per frame.

  // Iterate to least specific scope last to help preserve order in the local
  // variables view when stepping.
  for (var scope in filterScopes(frame).reversed) {
    final properties = await debugger.getProperties(scope.object.objectId);
    allProperties.addAll(properties);
  }

  if (frame.returnValue != null && frame.returnValue.type != 'undefined') {
    allProperties.add(
      Property({
        'name': 'return',
        'value': frame.returnValue,
      }),
    );
  }

  allProperties.removeWhere((property) {
    final value = property.value;

    // TODO(#786) Handle these correctly rather than just suppressing them.
    // We should never see a raw JS class. The only case where this happens is a
    // Dart generic function, where the type arguments get passed in as
    // parameters. Hide those.
    return (value.type == 'function' &&
            value.description.startsWith('class ')) ||
        (value.type == 'object' && value.description == 'dart.LegacyType.new');
  });

  return allProperties;
}

/// Filters the provided frame scopes to those that are pertinent for Dart
/// debugging.
List<WipScope> filterScopes(WipCallFrame frame) {
  // For RequireJS modules, the last three scopes are generally
  // `[unnamed closure] [script] [global]` in that order. We never want the
  // global and script scopes. We don't want the last closure scope - that's the
  // Dart SDK scope, and contains hundreds or thousands of properties (as does
  // the global scope).

  // For AMD modules, the last two scopes are generally
  // `[named closure] [global]` in that order. The named closure is the Dart SDK
  // scope.

  // Below, we filter out the last (global) scope, the optional script scope,
  // and the first (named or unnamed) closure scope. In the future, we'll likey
  // have more rigourous ways to identify the SDK scope.

  var scopes = frame.getScopeChain().toList();

  if (scopes.isNotEmpty && scopes.last.scope == 'global') {
    scopes.removeLast();
  }

  if (scopes.isNotEmpty && scopes.last.scope == 'script') {
    scopes.removeLast();
  }

  if (scopes.isNotEmpty && scopes.last.scope == 'closure') {
    scopes.removeLast();
  }

  return scopes;
}
