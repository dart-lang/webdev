// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:webdev/src/command/configuration.dart';

void main() {
  ArgParser argParser;
  Directory tempDirectory;
  setUp(() {
    argParser = ArgParser()..addFlag('release');
    tempDirectory = Directory.systemTemp.createTempSync();
  });

  tearDown(() {
    tempDirectory?.deleteSync(recursive: true);
  });

  test('does not throw if the configuration file does not exist', () {
    ConfigurationLoader.load(filePath: 'foo.yaml');
  });

  test('loads configurations from the yaml file', () {
    var yamlFile = File(p.join(tempDirectory.path, 'webdev_test.yaml'))
      ..createSync();
    var configuration = ConfigurationLoader.load(filePath: yamlFile.path);
    expect(configuration.release, isFalse);
    yamlFile.writeAsStringSync('release: true');
    configuration = ConfigurationLoader.load(filePath: yamlFile.path);
    expect(configuration.release, isTrue);
  });

  test('arg configuration takes precedence to yaml configuration', () {
    var argResults = argParser.parse(['--release']);
    var yamlFile = File(p.join(tempDirectory.path, 'webdev_test.yaml'))
      ..createSync();
    yamlFile.writeAsStringSync('release: false');
    var configuration = ConfigurationLoader.load(
        argResults: argResults, filePath: yamlFile.path);
    expect(configuration.release, isTrue);
  });

  test('default configuration takes precedence to global defaults', () {
    var configuration = ConfigurationLoader.load();
    expect(configuration.release, isFalse);
    configuration = ConfigurationLoader.load(
        defaultConfiguration: Configuration(release: true));
    expect(configuration.release, isTrue);
  });

  test('arg configuration takes precedence to default configuration', () {
    var argResults = argParser.parse(['--release']);
    var configuration = ConfigurationLoader.load(
        defaultConfiguration: Configuration(release: false));
    expect(configuration.release, isFalse);
    configuration = ConfigurationLoader.load(
        defaultConfiguration: Configuration(release: false),
        argResults: argResults);
    expect(configuration.release, isTrue);
  });
}
