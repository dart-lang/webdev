// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/context.dart';
import 'fixtures/utilities.dart';

final context = TestContext.withWeakNullSafety(
  packageName: '_testPackage',
  webAssetsPath: 'web',
  dartEntryFileName: 'main.dart',
  htmlEntryFileName: 'index.html',
);

/// The directory for the general _test package.
final testDir = absolutePath(pathFromFixtures: p.join('_test'));

/// The directory for the _testPackage package (contained within dwds), which
/// imports _test.
final testPackageDir = absolutePath(pathFromFixtures: p.join('_testPackage'));

// This tests converting file Uris into our internal paths.
//
// These tests are separated out because we need a running isolate in order to
// look up packages.
// TODO(https://github.com/dart-lang/webdev/issues/1818): Switch test over for
// testing sound null-safety.
void main() {
  for (final compilationMode in CompilationMode.values) {
    group('$compilationMode |', () {
      for (final useDebuggerModuleNames in [false, true]) {
        group('Debugger module names: $useDebuggerModuleNames |', () {
          final appServerPath =
              compilationMode == CompilationMode.frontendServer
                  ? 'web/main.dart'
                  : 'main.dart';

          final serverPath =
              compilationMode == CompilationMode.frontendServer &&
                      useDebuggerModuleNames
                  ? 'packages/_testPackage/lib/test_library.dart'
                  : 'packages/_test_package/test_library.dart';

          final anotherServerPath =
              compilationMode == CompilationMode.frontendServer &&
                      useDebuggerModuleNames
                  ? 'packages/_test/lib/library.dart'
                  : 'packages/_test/library.dart';

          setUpAll(() async {
            await context.setUp(
              compilationMode: compilationMode,
              useDebuggerModuleNames: useDebuggerModuleNames,
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
