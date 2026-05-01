// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 5))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';

import 'test_utils.dart';
import 'webdev_aot_common.dart';

void main() {
  webdevAotTests(
    testRunner: TestRunner(
      ddcModuleFormat: ModuleFormat.ddc,
      canaryFeatures: true,
    ),
    serveArgs: ['--module-format', 'ddc', '--canary'],
  );
}
