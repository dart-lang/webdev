// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@TestOn('vm')

import 'package:test/test.dart';

import 'fixtures/context.dart';
import 'evaluate_common.dart';

void main() async {
  // Enable verbose logging for debugging.
  var debug = false;

  for (var soundNullSafety in [false, true]) {
    group('${soundNullSafety ? "sound" : "weak"} null safety |', () {
      for (var basePath in ['', 'abc']) {
        group('with base "$basePath" |', () {
          testAll(
            compilationMode: CompilationMode.buildDaemon,
            soundNullSafety: soundNullSafety,
            basePath: basePath,
            debug: debug,
          );
        });
      }
    });
  }
}
