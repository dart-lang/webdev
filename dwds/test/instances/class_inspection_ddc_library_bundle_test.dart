// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import '../fixtures/context.dart';
import 'common/class_inspection_common.dart';

void main() {
  // Enable verbose logging for debugging.
  final debug = false;
  final canaryFeatures = true;
  final compilationMode = CompilationMode.frontendServer;
  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    canaryFeatures: canaryFeatures,
    ddcModuleFormat: ModuleFormat.ddc,
  );

  group('Class |', () {
    tearDownAll(provider.dispose);
    runTests(
      provider: provider,
      compilationMode: compilationMode,
      canaryFeatures: canaryFeatures,
      debug: debug,
    );
  });
}
