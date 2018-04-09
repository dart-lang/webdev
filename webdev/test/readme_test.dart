// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('README contains help output', () async {
    var process = await runWebDev([]);
    var output = (await process.stdoutStream().join('\n')).trim();
    await process.shouldExit(0);

    var readme = new File('README.md');
    expect(readme.readAsStringSync(),
        contains('```console\n\$ webdev\n$output\n```'));
  });
}
