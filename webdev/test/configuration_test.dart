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
    var configuration = Configuration.fromArgs(null);
    expect(configuration.hostname, equals('localhost'));
  });

  test('arg configuration takes precedence to default configuration', () {
    var defaultConfiguration = Configuration.fromArgs(null);
    expect(defaultConfiguration.release, isFalse);
    var argResults = argParser.parse(['--release']);
    var argConfiguration = Configuration.fromArgs(argResults);
    expect(argConfiguration.release, isTrue);
  });
}
