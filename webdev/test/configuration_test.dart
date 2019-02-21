// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';
import 'package:test/test.dart';
import 'package:webdev/src/command/configuration.dart';

void main() {
  ArgParser argParser;
  setUp(() {
    argParser = ArgParser()..addFlag('release');
  });

  test('default configuration is correctly applied', () {
    var configuration = Configuration();
    expect(configuration.release, isFalse);
    configuration = Configuration(release: true);
    expect(configuration.release, isTrue);
  });

  test('arg configuration takes precedence to default configuration', () {
    var argResults = argParser.parse(['--release']);
    var configuration = Configuration(release: false);
    expect(configuration.release, isFalse);
    expect(configuration.mergeArgs(argResults).release, isTrue);
  });
}
