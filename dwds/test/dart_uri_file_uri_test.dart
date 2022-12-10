// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(seconds: 60))
import 'dart:io';

import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/context.dart';
import 'utils/version_compatibility.dart';

final context = TestContext(
    directory: p.join('..', 'fixtures', '_testPackageSound'),
    entry: p.join('..', 'fixtures', '_testPackageSound', 'web', 'main.dart'),
    path: 'index.html',
    pathToServe: 'web');

final dwdsDir = Directory.current.absolute.path;

/// The directory for the general _test package.
final testDir = p.join(p.dirname(dwdsDir), 'fixtures', '_testSound');

/// The directory for the _testPackage package (contained within dwds), which
/// imports _test.
final testPackageDir = context.workingDirectory;

// This tests converting file Uris into our internal paths.
//
// These tests are separated out because we need a running isolate in order to
// look up packages.
void main() {
  for (final nullSafetyMode in supportedNullSafetyModes) {
    for (final compilationMode in supportedCompilationModes(nullSafetyMode)) {
      group('$compilationMode |', () {
        for (final useDebuggerModuleNames in [false, true]) {
          group('Debugger module names: $useDebuggerModuleNames |', () {
            final appServerPath =
                compilationMode == CompilationMode.frontendServer
                    ? 'web/main.dart'
                    : 'main.dart';

            final packageNameForFrontendServer =
                nullSafetyMode == NullSafety.sound
                    ? '_testPackageSound'
                    : '_testPackage';
            final packageNameForBuildDaemon = nullSafetyMode == NullSafety.sound
                ? '_test_package_sound'
                : '_test_package';
            final anotherPackageNameForFrontendServer =
                nullSafetyMode == NullSafety.sound ? '_testSound' : '_test';
            final anotherPackageNameForBuildDaemon =
                nullSafetyMode == NullSafety.sound ? '_test_sound' : '_test';

            final serverPath = compilationMode ==
                        CompilationMode.frontendServer &&
                    useDebuggerModuleNames
                ? 'packages/$packageNameForFrontendServer/lib/test_library.dart'
                : 'packages/$packageNameForBuildDaemon/test_library.dart';

            final anotherServerPath = compilationMode ==
                        CompilationMode.frontendServer &&
                    useDebuggerModuleNames
                ? 'packages/$anotherPackageNameForFrontendServer/lib/library.dart'
                : 'packages/$anotherPackageNameForBuildDaemon/library.dart';

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
}
