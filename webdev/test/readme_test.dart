// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('help build', () => _readmeCheck(['help', 'build']));
  test('help serve', () => _readmeCheck(['help', 'serve']));
}

Future _readmeCheck(List<String> args) async {
  var process = await runWebDev(args);
  var output = (await process.stdoutStream().join('\n')).trim();
  await process.shouldExit(0);

  var readme = File('README.md');

  var contents = readme.readAsStringSync();
  var placeholder = '\$ webdev ${args.join(' ')}';
  contents =
      contents.substring(contents.indexOf(placeholder) + placeholder.length);
  contents = contents.substring(0, contents.indexOf('```'));
  expect(contents, equalsIgnoringWhitespace(output));
}
