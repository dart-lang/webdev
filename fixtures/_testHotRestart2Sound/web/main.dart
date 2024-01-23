// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:core';
import 'dart:html';

import 'package:_test_hot_restart1/library1.dart';
import 'package:_test_hot_restart2/library2.dart';

/// Tests for constant semantics across hot restart in DDC.
///
/// DDC has multiple layers of constant caching. Failing to clear them can
/// result in stale constants being referenced across hot restarts.
///
/// Cases tested include:
/// 1) Failing to clear all constant caches.
///   An old 'ConstObject' is returned, which fails to reflect the edited
///   'variableToModifyToForceRecompile'.
/// 2) Clearing constant caches but failing to clear constant containers.
///   Reloaded constants fail to compare with constants in the cache,
///   causing 'ConstantEqualityFailure's.

class ConstObject {
  const ConstObject();
  String get text => 'ConstObject('
      'reloadVariable: $variableToModifyToForceRecompile, '
      '${value1 == value2 ? 'ConstantEqualitySuccess' : 'ConstantEqualityFailure'})';
}

void main() {
  document.body!.innerHtml =
      'Program is running!\n${const ConstObject().text}\n';
}
