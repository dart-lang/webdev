// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'util.dart';
import 'version.dart';

class PackageException implements Exception {
  final List<PackageExceptionDetails> details;

  final String unsupportedArgument;

  PackageException(this.details, {this.unsupportedArgument});
}

class PackageExceptionDetails {
  final String error;
  final String description;
  final bool _missingDependency;

  const PackageExceptionDetails._(this.error,
      {this.description, bool missingDependency})
      : _missingDependency = missingDependency ?? false;

  static const noPubspecLock = PackageExceptionDetails._(
      '`pubspec.lock` does not exist.',
      description:
          'Run `$appName` in a Dart package directory. Run `pub get` first.',
      missingDependency: true);

  static PackageExceptionDetails missingDep(
          String pkgName, VersionConstraint constraint) =>
      PackageExceptionDetails._(
          'You must have a dependency on `$pkgName` in `pubspec.yaml`.',
          description: '''
# pubspec.yaml
dev_dependencies:
  $pkgName: $constraint''',
          missingDependency: true);

  @override
  String toString() => [error, description].join('\n');
}

Future _runPubDeps() async {
  var result = Process.runSync(pubPath, ['deps']);

  if (result.exitCode == 65 || result.exitCode == 66) {
    throw PackageException(
        [PackageExceptionDetails._((result.stderr as String).trim())]);
  }

  if (result.exitCode != 0) {
    throw ProcessException(
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

    var pubspecLock = loadYaml(await File(path).readAsString()) as YamlMap;

    var packages = pubspecLock['packages'] as YamlMap;
    return PubspecLock(packages);
  }

  List<PackageExceptionDetails> checkPackage(
      String pkgName, VersionConstraint constraint,
      {String forArgument, bool requireDirect}) {
    requireDirect ??= true;
    var issues = <PackageExceptionDetails>[];
    var missingDetails =
        PackageExceptionDetails.missingDep(pkgName, constraint);

    var pkgDataMap = (_packages == null) ? null : _packages[pkgName] as YamlMap;
    if (pkgDataMap == null) {
      issues.add(missingDetails);
    } else {
      var dependency = pkgDataMap['dependency'] as String;
      if (requireDirect && !dependency.startsWith('direct ')) {
        issues.add(missingDetails);
      }

      var source = pkgDataMap['source'] as String;
      if (source == 'hosted') {
        // NOTE: pkgDataMap['description'] should be:
        //           `{url: https://pub.dartlang.org, name: [pkgName]}`
        //       If a user is playing around here, they are on their own.

        var version = pkgDataMap['version'] as String;
        var pkgVersion = Version.parse(version);
        if (!constraint.allows(pkgVersion)) {
          var error = 'The `$pkgName` version – $pkgVersion – is not '
              'within the allowed constraint – $constraint.';
          issues.add(PackageExceptionDetails._(error));
        }
      } else {
        // NOTE: Intentionally not checking non-hosted dependencies: git, path
        //       If a user is playing around here, they are on their own.
      }
    }
    return issues;
  }
}

Future<List<PackageExceptionDetails>> _validateBuildDaemonVersion(
    PubspecLock pubspecLock) async {
  var buildDaemonConstraint = '^0.4.0';

  var issues = <PackageExceptionDetails>[];

  var buildDaemonIssues = pubspecLock.checkPackage(
    'build_daemon',
    VersionConstraint.parse(buildDaemonConstraint),
  );

  // Only warn of build_daemon issues if they have a dependency on the package.
  if (buildDaemonIssues.any((issue) => !issue._missingDependency)) {
    var info = await _latestPackageInfo();
    var issuePreamble =
        'This version of webdev does not support the `build_daemon` '
        'protocol used by your version of `build_runner`.';
    // Check if the newer version supports the `build_daemon` transitive version
    // used by their application.
    if (info.isNewer &&
        pubspecLock
            .checkPackage('build_daemon', info.buildDaemonConstraint,
                requireDirect: false)
            .isEmpty) {
      issues.add(PackageExceptionDetails._('$issuePreamble\n'
          'A newer version of webdev is available which supports'
          'your version of the `build_daemon`. Please update.'));
    } else {
      issues.add(PackageExceptionDetails._('$issuePreamble\n'
          'Please add a dev dependency on `build_daemon` with constraint: '
          '$buildDaemonConstraint'));
    }
  }
  return issues;
}

Future<void> checkPubspecLock(PubspecLock pubspecLock,
    {@required bool requireBuildWebCompilers}) async {
  var issues = <PackageExceptionDetails>[];

  issues.addAll(pubspecLock.checkPackage(
      'build_runner', VersionConstraint.parse('>=1.3.0 <2.0.0')));

  if (requireBuildWebCompilers) {
    issues.addAll(pubspecLock.checkPackage(
        'build_web_compilers', VersionConstraint.parse('>=1.2.0 <2.0.0')));
  }

  issues.addAll(await _validateBuildDaemonVersion(pubspecLock));

  if (issues.isNotEmpty) {
    throw PackageException(issues);
  }
}

class _PackageInfo {
  final Version version;
  final VersionConstraint buildDaemonConstraint;
  final bool isNewer;
  _PackageInfo(this.version, this.buildDaemonConstraint, this.isNewer);
}

/// Returns the package info for the latest webdev release.
Future<_PackageInfo> _latestPackageInfo() async {
  var response = await get('https://pub.dartlang.org/api/packages/webdev');
  var responseObj = json.decode(response.body);
  var pubVersionString = responseObj['latest']['pubspec']['version'] as String;
  var buildDaemonConfig = responseObj['latest']['pubspec']['dev_dependencies']
      ['build_demon'] as String;
  var buildDaemonConstraint = buildDaemonConfig != null
      ? VersionConstraint.parse(buildDaemonConfig)
      // This should never be satisfied.
      : VersionConstraint.parse('0.0.0');
  var pubVersion = Version.parse(pubVersionString);
  var currentVersion = Version.parse(packageVersion);
  return _PackageInfo(pubVersion, buildDaemonConstraint,
      currentVersion.compareTo(pubVersion) < 0);
}
