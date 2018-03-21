// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'util.dart';

class PackageException implements Exception {
  final List<PackageExceptionDetails> details;

  PackageException._(this.details);
}

class PackageExceptionDetails {
  final String error;
  final String description;

  const PackageExceptionDetails._(this.error, {this.description});

  static const noPubspecLock = const PackageExceptionDetails._(
      '`pubspec.lock` does not exist.',
      description:
          'Run `webdev` in a Dart package directory. Run `pub get` first.');

  static const noBuildRunnerDep = const PackageExceptionDetails._(
      'A dependency on `build_runner` was not found.',
      description:
          'You must have a dependency on `build_runner` in `pubspec.yaml`. '
          'It can be in either `dependencies` or `dev_dependencies`.');

  static const noBuildWebCompilersDep = const PackageExceptionDetails._(
      'A dependency on `build_web_compilers` was not found.',
      description:
          'You must have a dependency on `build_web_compilers` in `pubspec.yaml` '
          'or transitively via another dependency.');

  @override
  String toString() => [error, description].join('\n');
}

Future checkPubspecLock() async {
  var file = new File('pubspec.lock');
  if (!file.existsSync()) {
    throw new PackageException._([PackageExceptionDetails.noPubspecLock]);
  }

  var pubspecLock = loadYaml(await file.readAsString()) as YamlMap;

  var packages = pubspecLock['packages'] as YamlMap;

  var issues = <PackageExceptionDetails>[];

  var buildRunner = packages['build_runner'] as YamlMap;
  if (buildRunner == null) {
    issues.add(PackageExceptionDetails.noBuildRunnerDep);
  } else {
    var dependency = buildRunner['dependency'] as String;
    if (!dependency.startsWith('direct ')) {
      issues.add(PackageExceptionDetails.noBuildRunnerDep);
    }

    var version = buildRunner['version'] as String;
    if (version == null) {
      // TODO: warning?
    } else {
      var buildRunnerVersion = new Version.parse(version);

      if (!supportedBuildRunnerVersionRange.allows(buildRunnerVersion)) {
        var error = 'The `build_runner` version – $buildRunnerVersion – is not '
            'within the supported range – $supportedBuildRunnerVersionRange.';
        issues.add(new PackageExceptionDetails._(error));
      }
    }

    var source = buildRunner['source'] as String;
    if (source == 'hosted') {
      //var description = buildRunner['description'] as YamlMap;
      // TODO: check for `{url: https://pub.dartlang.org, name: build_runner}`
      // If not, print a warning
    } else {
      // TODO: print a warning that we're assuming hosted
    }
  }

  var buldWebCompilers = packages['build_web_compilers'];
  if (buldWebCompilers == null) {
    issues.add(PackageExceptionDetails.noBuildWebCompilersDep);
  }

  if (issues.isNotEmpty) {
    throw new PackageException._(issues);
  }
}
