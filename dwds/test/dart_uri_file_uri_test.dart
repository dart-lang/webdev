// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

// This tests converting file Uris into our internal paths.
//
// These tests are separated out because we need a running isolate in order to
// look up packages.
void main() {
  final provider = TestSdkConfigurationProvider();
  tearDownAll(provider.dispose);

  final testProject = TestProject.testWithSoundNullSafety;
  final testPackageProject = TestProject.testPackageWithSoundNullSafety();

  /// The directory for the general _test package.
  final testDir = testProject.absolutePackageDirectory;

  /// The directory for the _testPackage package (contained within dwds),
  /// which imports _test.
  final testPackageDir = testPackageProject.absolutePackageDirectory;

  final context = TestContext(testPackageProject, provider);

  for (final compilationMode in CompilationMode.values) {
    group('$compilationMode |', () {
      for (final useDebuggerModuleNames in [false, true]) {
        group('Debugger module names: $useDebuggerModuleNames |', () {
          final appServerPath =
              compilationMode == CompilationMode.frontendServer
                  ? 'web/main.dart'
                  : 'main.dart';

          final serverPath = compilationMode ==
                      CompilationMode.frontendServer &&
                  useDebuggerModuleNames
              ? 'packages/${testPackageProject.packageDirectory}/lib/test_library.dart'
              : 'packages/${testPackageProject.packageName}/test_library.dart';

          final anotherServerPath =
              compilationMode == CompilationMode.frontendServer &&
                      useDebuggerModuleNames
                  ? 'packages/${testProject.packageDirectory}/lib/library.dart'
                  : 'packages/${testProject.packageName}/library.dart';

          setUpAll(() async {
            await context.setUp(
              testSettings: TestSettings(
                compilationMode: compilationMode,
                useDebuggerModuleNames: useDebuggerModuleNames,
              ),
            );
          });

          tearDownAll(() async {
            await context.tearDown();
          });

          test('file path to org-dartlang-app', () {
            final webMain =
                Uri.file(p.join(testPackageDir, 'web', 'main.dart'));
            final uri = DartUri('$webMain');
            expect(uri.serverPath, appServerPath);
          });

          test('file path to this package', () {
            final testPackageLib =
                Uri.file(p.join(testPackageDir, 'lib', 'test_library.dart'));
            final uri = DartUri('$testPackageLib');
            expect(uri.serverPath, serverPath);
          });

          test('file path to another package', () {
            final testLib = Uri.file(p.join(testDir, 'lib', 'library.dart'));
            final dartUri = DartUri('$testLib');
            expect(dartUri.serverPath, anotherServerPath);
          });
        });
      }
    });
  }
}
