// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'evaluate_common.dart';
import 'fixtures/context.dart';
import 'fixtures/project.dart';

void main() async {
  // Enable verbose logging for debugging.
  final debug = false;

  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    ddcModuleFormat: ModuleFormat.ddc,
    canaryFeatures: true,
  );
  tearDownAll(provider.dispose);

  for (final useDebuggerModuleNames in [false, true]) {
    group('Debugger module names: $useDebuggerModuleNames |', () {
      group('DDC module system and canary |', () {
        for (final indexBaseMode in IndexBaseMode.values) {
          group(
            'with ${indexBaseMode.name} |',
            () {
              testAll(
                provider: provider,
                compilationMode: CompilationMode.frontendServer,
                indexBaseMode: indexBaseMode,
                useDebuggerModuleNames: useDebuggerModuleNames,
                debug: debug,
              );
            },
            // TODO(#2488): Restore the skip argument below, related to
            // https://github.com/dart-lang/sdk/issues/49277, once
            // https://github.com/dart-lang/webdev/issues/2488 is resolved.
            // skip: indexBaseMode == IndexBaseMode.base && Platform.isWindows,
          );
        }
      });
    });
  }
}
