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
          'Run `$appName` in a Dart package directory. Run `pub get` first.');

  static final noBuildRunnerDep = new PackageExceptionDetails._(
      'You must have a dependency on `build_runner` in `pubspec.yaml`.',
      description: '''
# pubspec.yaml
dev_dependencies:
  build_runner: $supportedBuildRunnerVersionConstraint''');

  @override
  String toString() => [error, description].join('\n');
}

Future _runPubDeps() async {
  var result = Process.runSync(pubPath, ['deps']);

  if (result.exitCode == 65 || result.exitCode == 66) {
    throw new PackageException._(
        [new PackageExceptionDetails._((result.stderr as String).trim())]);
  }

  if (result.exitCode != 0) {
    throw new ProcessException(
        pubPath,
        ['deps'],
        '***OUT***\n${result.stdout}\n***ERR***\n${result.stderr}\n***',
        exitCode);
  }
}

Future checkPubspecLock() async {
  await _runPubDeps();

  var pubspecLock =
      loadYaml(await new File('pubspec.lock').readAsString()) as YamlMap;

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

    var source = buildRunner['source'] as String;
    if (source == 'hosted') {
      // NOTE: buildRunner['description'] should be:
      //           `{url: https://pub.dartlang.org, name: build_runner}`
      //       If a user is playing around here, they are on their own.

      var version = buildRunner['version'] as String;
      var buildRunnerVersion = new Version.parse(version);
      if (!supportedBuildRunnerVersionConstraint.allows(buildRunnerVersion)) {
        var error = 'The `build_runner` version – $buildRunnerVersion – is not '
            'within the allowed constraint – $supportedBuildRunnerVersionConstraint.';
        issues.add(new PackageExceptionDetails._(error));
      }
    } else {
      // NOTE: Intentionally not checking non-hosted dependencies: git, path
      //       If a user is playing around here, they are on their own.
    }
  }

  if (issues.isNotEmpty) {
    throw new PackageException._(issues);
  }
}
