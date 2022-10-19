// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/args.dart';
import 'package:test/test.dart';
import 'package:webdev/src/command/configuration.dart';

void main() {
  late ArgParser argParser;
  setUp(() {
    argParser = ArgParser()
      ..addFlag('release')
      ..addFlag(launchInChromeFlag, defaultsTo: false)
      ..addOption(nullSafetyFlag, defaultsTo: nullSafetyAuto)
      ..addOption(userDataDirFlag, defaultsTo: null);
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

  test('user data directory defaults to null ', () {
    var argResults = argParser.parse(['']);
    var defaultConfiguration = Configuration.fromArgs(argResults);
    expect(defaultConfiguration.userDataDir, isNull);
  });

  test('can read user data dir from args ', () {
    var argResults =
        argParser.parse(['--launch-in-chrome', '--user-data-dir=tempdir']);
    var configuration = Configuration.fromArgs(argResults);
    expect(configuration.userDataDir, equals('tempdir'));
  });

  test('can set user data directory with launchInChrome ', () {
    var configuration =
        Configuration(launchInChrome: true, userDataDir: 'temp');
    expect(configuration.userDataDir, equals('temp'));
  });

  test('can set user data directory to auto with launchInChrome ', () {
    var configuration =
        Configuration(launchInChrome: true, userDataDir: 'auto');
    expect(configuration.userDataDir, equals('auto'));
  });

  test('must set launchInChrome is to true if using user data directory ', () {
    expect(() => Configuration(launchInChrome: false, userDataDir: 'temp'),
        throwsA(isA<InvalidConfiguration>()));
  });

  test('nullSafety defaults to auto', () {
    var argResults = argParser.parse(['']);
    var defaultConfiguration = Configuration.fromArgs(argResults);
    expect(defaultConfiguration.nullSafety, equals(nullSafetyAuto));
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

  test(
      'only top level directories or an empty target are allowed for '
      'outputInput', () {
    // Valid
    expect(() => Configuration(outputInput: ''), returnsNormally);
    expect(() => Configuration(outputInput: 'foo/'), returnsNormally);

    // Invalid
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
