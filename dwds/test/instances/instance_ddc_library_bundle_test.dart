// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/src/services/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import '../fixtures/context.dart';
import 'common/instance_common.dart';

void main() {
  // Enable verbose logging for debugging.
  final debug = false;
  final canaryFeatures = true;
  final moduleFormat = ModuleFormat.ddc;
  final compilationMode = CompilationMode.frontendServer;

  group('canary: $canaryFeatures |', () {
    final provider = TestSdkConfigurationProvider(
      canaryFeatures: canaryFeatures,
      verbose: debug,
      ddcModuleFormat: moduleFormat,
    );
    tearDownAll(provider.dispose);

    runTests(
      provider: provider,
      compilationMode: compilationMode,
      canaryFeatures: canaryFeatures,
      debug: debug,
    );
  });
}
