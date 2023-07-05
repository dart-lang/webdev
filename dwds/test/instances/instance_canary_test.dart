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

void main() {
  // Enable verbose logging for debugging.
  final debug = false;

  _runAllTests(
    canaryFeatures: true,
    compilationMode: CompilationMode.frontendServer,
    debug: debug,
  );
}

void _runAllTests({
  required bool canaryFeatures,
  required CompilationMode compilationMode,
  required bool debug,
}) {
  group('canaryFeatures: $canaryFeatures |', () {
    final provider = TestSdkConfigurationProvider(
      canaryFeatures: canaryFeatures,
      verbose: debug,
    );

    final project = TestProject.testScopesWithSoundNullSafety;

    setUpAll(() async {
      setCurrentLogWriter(debug: debug);
      // Cleanup project including compiled dart sdk.
      await project.cleanUp();
    });
    tearDownAll(provider.dispose);

    group('$compilationMode |', () {
      final context = TestContext(project, provider);
      late AppInspector inspector;

      setUpAll(() async {
        setCurrentLogWriter(debug: debug);
        await context.setUp(
          canaryFeatures: canaryFeatures,
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
  });
}
