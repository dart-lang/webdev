// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'evaluate_circular_common.dart';
import 'fixtures/context.dart';

void main() async {
  // Enable verbose logging for debugging.
  const debug = false;

  final provider = TestSdkConfigurationProvider(verbose: debug);
  tearDownAll(provider.dispose);

  testAll(
    provider: provider,
    compilationMode: CompilationMode.buildDaemon,
    debug: debug,
  );
}
