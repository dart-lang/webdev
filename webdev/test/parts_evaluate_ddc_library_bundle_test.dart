// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:dwds_test_common/integration/evaluate_parts.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';

import 'helpers/context.dart';

void main() async {
  // Enable verbose logging for debugging.
  const debug = false;

  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    ddcModuleFormat: ModuleFormat.ddc,
    canaryFeatures: true,
  );
  tearDownAll(provider.dispose);

  group('Build Daemon |', () {
    testAll(provider: provider, contextFactory: BuildDaemonTestContext.new);
  });

  group('Build Daemon and Frontend Server |', () {
    testAll(
      provider: provider,
      contextFactory: BuildDaemonAndFrontendServerTestContext.new,
    );
  });
}
