// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('help build', () => _readmeCheck(['help', 'build']));
  test('help serve', () => _readmeCheck(['help', 'serve']));
}

final _readmeContents = File('README.md').readAsStringSync();

Future _readmeCheck(List<String> args) async {
  var process = await runWebDev(args);
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
