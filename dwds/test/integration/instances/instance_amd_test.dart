// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/integration/instance.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:test/test.dart';
import '../fixtures/frontend_server_context.dart';


void main() {
  // Enable verbose logging for debugging.
  const debug = false;
  final moduleFormat = ModuleFormat.amd;

  group('canary: false | Frontend Server |', () {
    final canaryFeatures = false;
    
    final provider = TestSdkConfigurationProvider(
      canaryFeatures: canaryFeatures,
      verbose: debug,
      ddcModuleFormat: moduleFormat,
    );
    tearDownAll(provider.dispose);

    runTypeSystemVerificationTests(
      provider: provider,
      contextFactory: (project, provider) => FrontendServerTestContext(project, provider),
      canaryFeatures: canaryFeatures,
    );

    runTests(
      provider: provider,
      contextFactory: (project, provider) => FrontendServerTestContext(project, provider),
      canaryFeatures: canaryFeatures,
    );
  });

  group('canary: true | Frontend Server |', () {
    final canaryFeatures = true;
    
    final provider = TestSdkConfigurationProvider(
      canaryFeatures: canaryFeatures,
      verbose: debug,
      ddcModuleFormat: moduleFormat,
    );
    tearDownAll(provider.dispose);

    runTypeSystemVerificationTests(
      provider: provider,
      contextFactory: (project, provider) => FrontendServerTestContext(project, provider),
      canaryFeatures: canaryFeatures,
    );

    runTests(
      provider: provider,
      contextFactory: (project, provider) => FrontendServerTestContext(project, provider),
      canaryFeatures: canaryFeatures,
    );
  });
}
