// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Tags(['daily'])
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/integration/hot_restart.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';
import 'fixtures/frontend_server_context.dart';
import '../../../webdev/test/helpers/context.dart';

void main() {
  // Enable verbose logging for debugging.
  const debug = false;
  final canaryFeatures = false;
  final moduleFormat = ModuleFormat.amd;
  

  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    canaryFeatures: canaryFeatures,
    ddcModuleFormat: moduleFormat,
  );

  runTests(
    provider: provider,
    moduleFormat: moduleFormat,
    contextFactory: (project, provider) => BuildDaemonTestContext(project, provider),
    canaryFeatures: canaryFeatures,
  );
}
