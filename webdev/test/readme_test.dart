// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@OnPlatform({
  'windows': Skip('https://github.com/dart-lang/webdev/issues/711'),
})
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  final testRunner = TestRunner();
  setUpAll(testRunner.setUpAll);
  tearDownAll(testRunner.tearDownAll);

  test('help build', () => _readmeCheck(testRunner, ['help', 'build']));
  test('help serve', () => _readmeCheck(testRunner, ['help', 'serve']));
}

final _readmeContents = File('README.md').readAsStringSync();

Future _readmeCheck(TestRunner testRunner, List<String> args) async {
  var process = await testRunner.runWebDev(args);
  var output =
      (await process.stdoutStream().map((line) => line.trimRight()).join('\n'))
          .trim();
  await process.shouldExit(0);

  final firstLineStart =
      _readmeContents.indexOf(LineSplitter.split(output).first);

  expect(firstLineStart, greaterThanOrEqualTo(0));

  final sectionEnd = _readmeContents.indexOf('```', firstLineStart);
  expect(sectionEnd, greaterThan(firstLineStart));

  expect(
    _readmeContents.substring(firstLineStart, sectionEnd).trim(),
    output,
  );
}
