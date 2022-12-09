// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'fixtures/context.dart';
import 'evaluate_circular_common.dart';

void main() async {
  // Enable verbose logging for debugging.
  final debug = false;
  final sdkVersion = Version.parse(Platform.version.split(' ')[0]);
  final nullSafetyValues = (sdkVersion.major >= 3)
      ? [NullSafety.sound]
      : [NullSafety.sound, NullSafety.weak];

  for (var nullSafety in nullSafetyValues) {
    group('${nullSafety.name} null safety |', () {
      testAll(
        compilationMode: CompilationMode.buildDaemon,
        nullSafety: nullSafety,
        debug: debug,
      );
    });
  }
}
