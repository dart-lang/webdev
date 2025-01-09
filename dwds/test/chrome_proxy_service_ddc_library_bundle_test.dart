// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Tags(['daily'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';

import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:vm_service/vm_service.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

void main() {
  // Change to true to see verbose output from the tests.
  final debug = false;
  final moduleFormat = ModuleFormat.ddc;
  final canaryFeatures = true;
  final compilationMode = CompilationMode.frontendServer;

  final provider = TestSdkConfigurationProvider(
    verbose: debug,
    ddcModuleFormat: moduleFormat,
    canaryFeatures: canaryFeatures,
  );
  tearDownAll(provider.dispose);

  final context = TestContext(TestProject.testDdcLibraryBundle, provider);

  group('shared context', () {
    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        testSettings: TestSettings(
          enableExpressionEvaluation: true,
          verboseCompiler: false,
          moduleFormat: provider.ddcModuleFormat,
          canaryFeatures: provider.canaryFeatures,
          compilationMode: compilationMode,
        ),
      );
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    group('callServiceExtension', () {
      late ChromeProxyService service;

      setUp(() {
        setCurrentLogWriter(debug: debug);
        service = context.service;
      });

      test(
        'success',
        () async {
          final serviceMethod = 'ext.test.callServiceExtension';
          await context.tabConnection.runtime
              .evaluate('registerExtension("$serviceMethod");');

          // The non-string keys/values get auto json-encoded to match the vm
          // behavior.
          final args = {
            'bool': true,
            'list': [1, '2', 3],
            'map': {'foo': 'bar'},
            'num': 1.0,
            'string': 'hello',
            1: 2,
            false: true,
          };

          final result =
              await service.callServiceExtension(serviceMethod, args: args);
          expect(
            result.json,
            args.map(
              (k, v) => MapEntry(
                k is String ? k : jsonEncode(k),
                v is String ? v : jsonEncode(v),
              ),
            ),
          );
        },
        onPlatform: {
          'windows':
              const Skip('https://github.com/dart-lang/webdev/issues/711'),
        },
      );

      test(
        'failure',
        () async {
          final serviceMethod = 'ext.test.callServiceExtensionWithError';
          await context.tabConnection.runtime
              .evaluate('registerExtensionWithError("$serviceMethod");');

          final errorDetails = {'intentional': 'error'};
          expect(
            service.callServiceExtension(
              serviceMethod,
              args: {
                'code': '-32001',
                'details': jsonEncode(errorDetails),
              },
            ),
            throwsA(
              predicate(
                (dynamic error) =>
                    error is RPCError &&
                    error.code == -32001 &&
                    error.details == jsonEncode(errorDetails),
              ),
            ),
          );
        },
        onPlatform: {
          'windows':
              const Skip('https://github.com/dart-lang/webdev/issues/711'),
        },
      );
    });
  });
}
