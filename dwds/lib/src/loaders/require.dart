// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'strategy.dart';

/// A load strategy for the require-js module system.
class RequireStrategy extends LoadStrategy {
  @override
  final ReloadConfiguration reloadConfiguration;

  RequireStrategy(this.reloadConfiguration);

  @override
  String get id => 'require-js';

  @override
  // Libraries do not need to be imported with this strategy.
  String get importLibrariesSnippet => '';

  @override
  String get loadModuleSnippet => 'require';
}
