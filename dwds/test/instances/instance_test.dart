// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@Timeout(Duration(minutes: 2))

import 'package:test/test.dart';

import '../fixtures/context.dart';
import 'instance_common.dart';

void main() {
  // Enable verbose logging for debugging.
  final debug = false;

  for (var compilationMode in CompilationMode.values) {
    runTests(
      compilationMode: compilationMode,
      canaryFeatures: false,
      debug: debug,
    );
  }
}
