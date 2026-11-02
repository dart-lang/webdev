// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:dwds_test_common/integration/type_inspection.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';

import '../../fixtures/build_daemon_context.dart';

void main() {
  // Enable verbose logging for debugging.
  const debug = false;

  for (final canaryFeatures in [true]) {
    group('canary: $canaryFeatures | Build Daemon |', () {
      final provider = TestSdkConfigurationProvider(
        verbose: debug,
        canaryFeatures: canaryFeatures,
        ddcModuleFormat: ModuleFormat.ddc,
      );
      tearDownAll(provider.dispose);

      runTests(
        provider: provider,
        contextFactory: BuildDaemonTestContext.new,
        canaryFeatures: canaryFeatures,
      );
    });
  }
}
