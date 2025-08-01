// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/src/services/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import '../fixtures/context.dart';
import 'common/instance_inspection_common.dart';

void main() {
  // Enable verbose logging for debugging.
  const debug = false;
  final canaryFeatures = false;

  group('canary: $canaryFeatures |', () {
    final provider = TestSdkConfigurationProvider(
      verbose: debug,
      canaryFeatures: canaryFeatures,
      ddcModuleFormat: ModuleFormat.amd,
    );
    tearDownAll(provider.dispose);

    for (final compilationMode in CompilationMode.values) {
      runTests(
        provider: provider,
        compilationMode: compilationMode,
        canaryFeatures: canaryFeatures,
        debug: debug,
      );
    }
  });
}
