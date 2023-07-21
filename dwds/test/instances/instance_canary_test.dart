// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Tags(['daily'])
@Timeout(Duration(minutes: 2))

import 'package:dwds/src/debugging/inspector.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';

import '../fixtures/context.dart';
import '../fixtures/project.dart';
import 'common/instance_common.dart';

void main() {
  // Enable verbose logging for debugging.
  final debug = false;
  final canaryFeatures = true;

  group('canary: $canaryFeatures |', () {
    final provider = TestSdkConfigurationProvider(
      canaryFeatures: canaryFeatures,
      verbose: debug,
    );
    tearDownAll(provider.dispose);

    for (var compilationMode in CompilationMode.values) {
      _runCanaryModeVerificationTests(
        provider: provider,
        compilationMode: compilationMode,
        debug: debug,
      );

      runTests(
        provider: provider,
        compilationMode: compilationMode,
        canaryFeatures: canaryFeatures,
        debug: debug,
      );
    }
  });
}

void _runCanaryModeVerificationTests({
  required TestSdkConfigurationProvider provider,
  required CompilationMode compilationMode,
  required bool debug,
}) {
  final project = TestProject.testScopesWithSoundNullSafety;

  group('$compilationMode |', () {
    final context = TestContext(project, provider);
    late AppInspector inspector;

    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      await context.setUp(
        canaryFeatures: true,
        compilationMode: compilationMode,
      );
      final chromeProxyService = context.service;
      inspector = chromeProxyService.inspector;
    });

    tearDownAll(() async {
      await context.tearDown();
    });

    final url = 'org-dartlang-app:///example/scopes/main.dart';

    String libraryName(CompilationMode compilationMode) =>
        compilationMode == CompilationMode.frontendServer
            ? "example/scopes/main.dart"
            : "example/scopes/main";

    String libraryVariableTypeExpression(
      String variable,
      CompilationMode compilationMode,
    ) =>
        '''
            (function() {
              var dart = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk').dart;
              var libraryName = '${libraryName(compilationMode)}';
              var library = dart.getModuleLibraries(libraryName)['$url'];
              var x = library['$variable'];
              return dart.getReifiedType(x);
            })();
          ''';

    group('compiler', () {
      setUp(() => setCurrentLogWriter(debug: debug));

      test('uses new type system', () async {
        final remoteObject = await inspector.jsEvaluate(
          libraryVariableTypeExpression(
            'libraryPublicFinal',
            compilationMode,
          ),
        );
        expect(remoteObject.json['className'], 'dart_rti.Rti.new');
      });
    });
  });
}
