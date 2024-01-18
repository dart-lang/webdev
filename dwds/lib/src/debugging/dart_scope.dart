// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/utilities/domain.dart';
import 'package:dwds/src/utilities/objects.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// The regular expressions used to filter out temp variables.
/// Needs to be kept in sync with SDK repo.
///
/// TODO(annagrin) - use an alternative way to identify
/// synthetic variables.
/// Issue: https://github.com/dart-lang/sdk/issues/44262
final ddcTemporaryVariableRegExp = RegExp(r'^t(\$[0-9]*)+\w*$');
final ddcTemporaryTypeVariableRegExp = RegExp(r'^__t[\$\w*]+$');

/// Temporary variable regex before SDK changes for patterns.
/// TODO(annagrin): remove after dart 3.0 is stable.
final previousDdcTemporaryVariableRegExp =
    RegExp(r'^(t[0-9]+\$?[0-9]*|__t[\$\w*]+)$');

/// Find the visible Dart variables from a JS Scope Chain, coming from the
/// scopeChain attribute of a Chrome CallFrame corresponding to [frame].
///
/// See chromedevtools.github.io/devtools-protocol/tot/Debugger#type-CallFrame.
Future<List<Property>> visibleVariables({
  required AppInspectorInterface inspector,
  required WipCallFrame frame,
}) async {
  final allProperties = <Property>[];

  if (frame.thisObject.type != 'undefined') {
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
    final objectId = scope.object.objectId;
    if (objectId != null) {
      final properties = await inspector.getProperties(objectId);
      allProperties.addAll(properties);
    }
  }

  if (frame.returnValue != null && frame.returnValue!.type != 'undefined') {
    allProperties.add(
      Property({
        'name': 'return',
        'value': frame.returnValue,
      }),
    );
  }

  allProperties.removeWhere((property) {
    final value = property.value;
    if (value == null) return true;

    final type = value.type;
    if (type == 'undefined') return true;

    final description = value.description ?? '';
    final name = property.name ?? '';

    // TODO(#786) Handle these correctly rather than just suppressing them.
    // We should never see a raw JS class. The only case where this happens is a
    // Dart generic function, where the type arguments get passed in as
    // parameters. Hide those.
    return (type == 'function' && description.startsWith('class ')) ||
        previousDdcTemporaryVariableRegExp.hasMatch(name) ||
        ddcTemporaryVariableRegExp.hasMatch(name) ||
        ddcTemporaryTypeVariableRegExp.hasMatch(name) ||
        (type == 'object' && description == 'dart.LegacyType.new');
  });

  return allProperties;
}

/// Filters the provided frame scopes to those that are pertinent for Dart
/// debugging.
List<WipScope> filterScopes(WipCallFrame frame) {
  final scopes = frame.getScopeChain().toList();
  // Remove outer scopes up to and including the Dart SDK.
  while (
      scopes.isNotEmpty && !(scopes.last.name?.startsWith('load__') ?? false)) {
    scopes.removeLast();
  }
  if (scopes.isNotEmpty) scopes.removeLast();
  return scopes;
}
