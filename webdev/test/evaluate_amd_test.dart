// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'helpers/context.dart';
import 'package:dwds_test_common/fixtures/project.dart';
import 'package:dwds_test_common/integration/evaluate.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';

void main() async {
  // Enable verbose logging for debugging.
  const debug = false;

  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    ddcModuleFormat: ModuleFormat.amd,
  );
  tearDownAll(provider.dispose);

  group('Build Daemon |', () {
    testAll(provider: provider, contextFactory: (project, provider) => BuildDaemonTestContext(project, provider));
  });
}
