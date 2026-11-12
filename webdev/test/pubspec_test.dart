// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:webdev/src/pubspec.dart';
import 'package:yaml/yaml.dart';

/// A lock file with hosted `build_runner`, `build_web_compilers`, and optional
/// `build_daemon`.
PubspecLock _lockWith({
  String buildWebCompilersVersion = '4.9.0',
  String? buildDaemonVersion,
}) => PubspecLock(
  loadYaml('''
build_runner:
  source: hosted
  version: "2.5.0"
build_web_compilers:
  source: hosted
  version: "$buildWebCompilersVersion"
${buildDaemonVersion == null ? '' : '''
build_daemon:
  source: hosted
  version: "$buildDaemonVersion"
'''}''') as YamlMap,
);

void main() {
  group('checkPubspecLock with build_daemon', () {
    test('allows build_daemon 4.1.4 or newer', () async {
      await checkPubspecLock(
        _lockWith(buildDaemonVersion: '4.1.4'),
        requireBuildWebCompilers: true,
      );
    });
  });

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
