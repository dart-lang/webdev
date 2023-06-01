// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'evaluate_circular_common.dart';
import 'fixtures/context.dart';
import 'fixtures/project.dart';

void main() async {
  // Enable verbose logging for debugging.
  final debug = false;

  final provider = TestSdkConfigurationProvider(verbose: debug);
  tearDownAll(provider.dispose);

  group('Context with circular dependencies |', () {
    for (var nullSafety in NullSafety.values) {
      group('${nullSafety.name} null safety |', () {
        for (var indexBaseMode in IndexBaseMode.values) {
          group(
            'with ${indexBaseMode.name} |',
            () {
              testAll(
                provider: provider,
                compilationMode: CompilationMode.frontendServer,
                indexBaseMode: indexBaseMode,
                nullSafety: nullSafety,
                useDebuggerModuleNames: true,
                debug: debug,
              );
            },
            skip:
                // https://github.com/dart-lang/sdk/issues/49277
                indexBaseMode == IndexBaseMode.base && Platform.isWindows,
          );
        }
      });
    }
  });
}
