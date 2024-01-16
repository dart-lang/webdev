// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))

import 'dart:io';

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
  );
  tearDownAll(provider.dispose);

  for (var useDebuggerModuleNames in [false, true]) {
    group('Debugger module names: $useDebuggerModuleNames |', () {
      final nullSafety = NullSafety.sound;
      group('${nullSafety.name} null safety | DDC module system |', () {
        for (var indexBaseMode in IndexBaseMode.values) {
          group(
            'with ${indexBaseMode.name} |',
            () {
              testAll(
                provider: provider,
                compilationMode: CompilationMode.frontendServer,
                indexBaseMode: indexBaseMode,
                nullSafety: nullSafety,
                useDebuggerModuleNames: useDebuggerModuleNames,
                debug: debug,
              );
            },
            // https://github.com/dart-lang/sdk/issues/49277
            skip: indexBaseMode == IndexBaseMode.base && Platform.isWindows,
          );
        }
      });
    });
  }
}
