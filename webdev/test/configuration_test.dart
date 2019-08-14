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

  test('tlsCertKey and tlsCertChain must be provided together', () {
    expect(() => Configuration(tlsCertKey: 'blah'),
        throwsA(isA<InvalidConfiguration>()));
    expect(() => Configuration(tlsCertChain: 'blah'),
        throwsA(isA<InvalidConfiguration>()));
  });

  test('must provide a debug port when launchInChrome is false ', () {
    expect(() => Configuration(debug: true, launchInChrome: false),
        throwsA(isA<InvalidConfiguration>()));
  });

  test(
      'must not provide debug related configuartion when enableInjectedClient '
      'is false', () {
    expect(() => Configuration(enableInjectedClient: false, debug: true),
        throwsA(isA<InvalidConfiguration>()));
    expect(
        () => Configuration(enableInjectedClient: false, debugExtension: true),
        throwsA(isA<InvalidConfiguration>()));
    expect(
        () => Configuration(enableInjectedClient: false, chromeDebugPort: 8080),
        throwsA(isA<InvalidConfiguration>()));
  });

  test('only top level directories are allowed for outputInput', () {
    expect(() => Configuration(outputInput: '.'),
        throwsA(isA<InvalidConfiguration>()));
    expect(() => Configuration(outputInput: '../'),
        throwsA(isA<InvalidConfiguration>()));
    expect(() => Configuration(outputInput: '../foo'),
        throwsA(isA<InvalidConfiguration>()));
    expect(() => Configuration(outputInput: 'foo/bar'),
        throwsA(isA<InvalidConfiguration>()));
    expect(() => Configuration(outputInput: 'foo/../'),
        throwsA(isA<InvalidConfiguration>()));
  });
}
