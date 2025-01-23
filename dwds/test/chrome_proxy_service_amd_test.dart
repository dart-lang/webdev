// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Tags(['daily'])
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'common/chrome_proxy_service_common.dart';
import 'fixtures/context.dart';

void main() {
  // Enable verbose logging for debugging.
  final debug = false;
  final canaryFeatures = false;
  final moduleFormat = ModuleFormat.amd;
  final compilationMode = CompilationMode.buildDaemon;

  group('canary: $canaryFeatures |', () {
    final provider = TestSdkConfigurationProvider(
      verbose: debug,
      canaryFeatures: canaryFeatures,
      ddcModuleFormat: moduleFormat,
    );
    tearDownAll(provider.dispose);

    runTests(
      provider: provider,
      moduleFormat: moduleFormat,
      compilationMode: compilationMode,
      canaryFeatures: canaryFeatures,
      debug: debug,
    );
  });
}
