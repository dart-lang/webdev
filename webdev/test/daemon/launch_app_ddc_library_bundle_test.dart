// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';

import '../test_utils.dart';
import 'launch_app_common.dart';

void main() {
  group('Build Daemon', () {
    launchAppTests(
      testRunner: TestRunner(
        canaryFeatures: true,
        webHotReload: false,
        ddcModuleFormat: ModuleFormat.ddc,
      ),
    );
  });

  group('Build Daemon and Frontend Server', () {
    launchAppTests(
      testRunner: TestRunner(
        canaryFeatures: true,
        webHotReload: true,
        ddcModuleFormat: ModuleFormat.ddc,
      ),
    );
  });
}
