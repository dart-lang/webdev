// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@OnPlatform({
  'windows': Skip('https://github.com/dart-lang/webdev/issues/711'),
})
import 'package:build_verify/build_verify.dart';
import 'package:test/test.dart';

main() {
  test(
      'ensure_build',
      () => expectBuildClean(packageRelativeDirectory: 'dwds', customCommand: [
            'PUB',
            'run',
            'build_runner',
            'build',
            '--delete-conflicting-outputs',
            '--build-filter=lib/src/version.dart'
          ]));
}
