// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'util.dart';

class PackageException implements Exception {
  final List<PackageExceptionDetails> details;

  final String unsupportedArgument;

  PackageException(this.details, {this.unsupportedArgument});
}

class PackageExceptionDetails {
  final String error;
  final String description;

  const PackageExceptionDetails._(this.error, {this.description});

  static const noPubspecLock = const PackageExceptionDetails._(
      '`pubspec.lock` does not exist.',
      description:
          'Run `$appName` in a Dart package directory. Run `pub get` first.');

  static PackageExceptionDetails missingDep(
          String pkgName, VersionConstraint constraint) =>
      new PackageExceptionDetails._(
          'You must have a dependency on `$pkgName` in `pubspec.yaml`.',
          description: '''
# pubspec.yaml
dev_dependencies:
  $pkgName: $constraint''');

  @override
  String toString() => [error, description].join('\n');
}

Future _runPubDeps() async {
  var result = Process.runSync(pubPath, ['deps']);

  if (result.exitCode == 65 || result.exitCode == 66) {
    throw new PackageException(
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

class PubspecLock {
  final YamlMap _packages;

  PubspecLock(this._packages);

  static Future<PubspecLock> read([String path]) async {
    path ??= 'pubspec.lock';
    await _runPubDeps();

    var pubspecLock = loadYaml(await new File(path).readAsString()) as YamlMap;

    var packages = pubspecLock['packages'] as YamlMap;
    return new PubspecLock(packages);
  }

  List<PackageExceptionDetails> checkPackage(
      String pkgName, VersionConstraint constraint,
      {String forArgument}) {
    var issues = <PackageExceptionDetails>[];
    var missingDetails =
        PackageExceptionDetails.missingDep(pkgName, constraint);

    var pkgDataMap = (_packages == null) ? null : _packages[pkgName] as YamlMap;
    if (pkgDataMap == null) {
      issues.add(missingDetails);
    } else {
      var dependency = pkgDataMap['dependency'] as String;
      if (!dependency.startsWith('direct ')) {
        issues.add(missingDetails);
      }

      var source = pkgDataMap['source'] as String;
      if (source == 'hosted') {
        // NOTE: pkgDataMap['description'] should be:
        //           `{url: https://pub.dartlang.org, name: [pkgName]}`
        //       If a user is playing around here, they are on their own.

        var version = pkgDataMap['version'] as String;
        var pkgVersion = new Version.parse(version);
        if (!constraint.allows(pkgVersion)) {
          var error = 'The `$pkgName` version – $pkgVersion – is not '
              'within the allowed constraint – $constraint.';
          issues.add(new PackageExceptionDetails._(error));
        }
      } else {
        // NOTE: Intentionally not checking non-hosted dependencies: git, path
        //       If a user is playing around here, they are on their own.
      }
    }
    return issues;
  }
}

Future<void> checkPubspecLock(PubspecLock pubspecLock,
    {@required bool requireBuildWebCompilers}) async {
  var issues = <PackageExceptionDetails>[];

  issues.addAll(pubspecLock.checkPackage(
      'build_runner', new VersionConstraint.parse('>=0.8.10 <0.11.0')));

  if (requireBuildWebCompilers) {
    issues.addAll(pubspecLock.checkPackage(
        'build_web_compilers', new VersionConstraint.parse('>=0.3.6 <0.5.0')));
  }

  if (issues.isNotEmpty) {
    throw new PackageException(issues);
  }
}
