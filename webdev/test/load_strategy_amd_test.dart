// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:dwds_test_common/integration/load_strategy.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';

import '../../dwds/test/integration/fixtures/frontend_server_context.dart';
import 'helpers/context.dart';

void main() {

  // Enable verbose logging for debugging.
  const debug = false;

  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    ddcModuleFormat: ModuleFormat.amd,
  );
  tearDownAll(provider.dispose);

  group('Build Daemon |', () {
    testAll(
      provider: provider,
      contextFactory: BuildDaemonTestContext.new,
    );
  });

  group('Frontend Server |', () {
    testAll(
      provider: provider,
      contextFactory: FrontendServerTestContext.new,
    );
  });
}
