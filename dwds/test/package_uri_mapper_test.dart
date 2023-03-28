// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))

import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:file/local.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/project.dart';

void main() {
  final project = TestProject.testPackageWithSoundNullSafety();

  for (final useDebuggerModuleNames in [true, false]) {
    group(
        'Package uri mapper with debugger module names: '
        ' $useDebuggerModuleNames |', () {
      final fileSystem = LocalFileSystem();

      final packageUri = Uri(
        scheme: 'package',
        path: '${project.packageName}/test_library.dart',
      );

      final serverPath = useDebuggerModuleNames
          ? 'packages/${project.packageDirectory}/lib/test_library.dart'
          : '/packages/${project.packageName}/test_library.dart';

      final resolvedPath =
          '/webdev/fixtures/${project.packageDirectory}/lib/test_library.dart';

      final testPackageSoundPath = project.absolutePackageDirectory;
      final packageConfigFile = Uri.file(
        p.join(
          testPackageSoundPath,
          '.dart_tool',
          'package_config.json',
        ),
      );

      late final PackageUriMapper packageUriMapper;
      setUpAll(() async {
        // Note: Run `dart pub upgrade` before the test cases to fix
        // https://github.com/dart-lang/webdev/issues/1834:
        await Process.run(
          'dart',
          ['pub', 'upgrade'],
          workingDirectory: testPackageSoundPath,
        );

        packageUriMapper = await PackageUriMapper.create(
          fileSystem,
          packageConfigFile,
          useDebuggerModuleNames: useDebuggerModuleNames,
        );
      });

      test('Can convert package urls to server paths', () {
        expect(packageUriMapper.packageUriToServerPath(packageUri), serverPath);
      });

      test('Can convert server paths to file paths', () {
        expect(
          packageUriMapper.serverPathToResolvedUri(serverPath),
          isA<Uri>()
              .having((uri) => uri.scheme, 'scheme', 'file')
              .having((uri) => uri.path, 'path', endsWith(resolvedPath)),
        );
      });
    });
  }
}
