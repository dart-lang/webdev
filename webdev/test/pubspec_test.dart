// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:webdev/src/pubspec.dart';
import 'package:yaml/yaml.dart';

/// A lock file with hosted `build_runner` and `build_web_compilers`, and no
/// `build_daemon`, so checking it does not need the network.
PubspecLock _lockWith({required String buildWebCompilersVersion}) =>
    PubspecLock(
      loadYaml('''
build_runner:
  source: hosted
  version: "2.5.0"
build_web_compilers:
  source: hosted
  version: "$buildWebCompilersVersion"
''')
          as YamlMap,
    );

void main() {
  group('checkPubspecLock with deprecated-js-interop', () {
    test('allows an older build_web_compilers without the flag', () async {
      await checkPubspecLock(
        _lockWith(buildWebCompilersVersion: '4.8.0'),
        requireBuildWebCompilers: true,
      );
    });

    test('rejects an older build_web_compilers with the flag', () async {
      await expectLater(
        checkPubspecLock(
          _lockWith(buildWebCompilersVersion: '4.8.0'),
          requireBuildWebCompilers: true,
          deprecatedJsInteropArgument: 'no-deprecated-js-interop',
        ),
        throwsA(
          isA<PackageException>()
              .having(
                (e) => e.unsupportedArgument,
                'unsupportedArgument',
                'no-deprecated-js-interop',
              )
              .having(
                (e) => e.details.single.error,
                'error',
                contains('build_web_compilers'),
              ),
        ),
      );
    });

    test('allows a build_web_compilers that supports the flag', () async {
      await checkPubspecLock(
        _lockWith(buildWebCompilersVersion: '4.9.0'),
        requireBuildWebCompilers: true,
        deprecatedJsInteropArgument: 'deprecated-js-interop',
      );
    });

    test('skips the check without a build_web_compilers requirement', () async {
      await checkPubspecLock(
        _lockWith(buildWebCompilersVersion: '4.8.0'),
        requireBuildWebCompilers: false,
        deprecatedJsInteropArgument: 'deprecated-js-interop',
      );
    });
  });
}
