// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'evaluate_common.dart';
import 'fixtures/context.dart';
import 'fixtures/project.dart';

void main() async {
  // Enable verbose logging for debugging.
  const debug = false;

  group('Canary: true |', () {
    final provider = TestSdkConfigurationProvider(
      verbose: debug,
      ddcModuleFormat: ModuleFormat.ddc,
      canaryFeatures: true,
    );
    tearDownAll(provider.dispose);

    group('Build Daemon |', () {
      testAll(
        provider: provider,
        compilationMode: CompilationMode.buildDaemon,
        debug: debug,
      );
    });

    group('Frontend Server |', () {
      for (final useDebuggerModuleNames in [false, true]) {
        group('Debugger module names: $useDebuggerModuleNames |', () {
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
              // https://github.com/dart-lang/sdk/issues/49277
              skip: indexBaseMode == IndexBaseMode.base && Platform.isWindows
                  ? 'Skipped on Windows when indexBaseMode is base. See issue: https://github.com/dart-lang/sdk/issues/49277'
                  : null,
            );
          }
        });
      }
    });
  });

  group('Canary: false |', () {
    final provider = TestSdkConfigurationProvider(
      verbose: debug,
      ddcModuleFormat: ModuleFormat.ddc,
      canaryFeatures: false,
    );
    tearDownAll(provider.dispose);

    // Build Daemon tests for non-canary if desired, or skip.
    // Given the prompt emphasized "migrating" and "DDC Library Bundle", and
    // frontend_server_ddc_evaluate_test.dart existed (canary: false), we include it.
    // Build Daemon was not explicitly tested with DDC non-canary before, but we might as well add it if it works.
    // However, to mimic existing coverage accurately:
    // frontend_server_ddc_evaluate_test.dart (canary: false) existed.
    // frontend_server_ddc_library_bundle_evaluate_test.dart (canary: true) existed.
    // I will add Frontend Server tests here.
    // I will also add Build Daemon tests as the user specifically requested "DDC Library Bundle tests should test build_runner ... pathways".

    group('Build Daemon |', () {
      testAll(
        provider: provider,
        compilationMode: CompilationMode.buildDaemon,
        debug: debug,
      );
    });

    group('Frontend Server |', () {
      for (final useDebuggerModuleNames in [false, true]) {
        group('Debugger module names: $useDebuggerModuleNames |', () {
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
              // https://github.com/dart-lang/sdk/issues/49277
              skip: indexBaseMode == IndexBaseMode.base && Platform.isWindows,
            );
          }
        });
      }
    });
  });
}
