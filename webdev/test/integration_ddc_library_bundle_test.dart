// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 3))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';

import 'integration_common.dart';
import 'test_utils.dart';

void main() {
  integrationTests(
    testRunner: TestRunner(
      webHotReload: false,
      ddcModuleFormat: ModuleFormat.ddc,
    ),
  );
}
