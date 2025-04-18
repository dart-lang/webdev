// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

import 'util.dart';
import 'version.dart';

class PackageException implements Exception {
  final List<PackageExceptionDetails> details;

  final String? unsupportedArgument;

  PackageException(this.details, {this.unsupportedArgument});
}

class PackageExceptionDetails {
  final String error;
  final String? description;
  final bool _missingDependency;

  const PackageExceptionDetails._(this.error,
      {this.description, bool missingDependency = false})
      : _missingDependency = missingDependency;

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
  final result = Process.runSync(dartPath, ['pub', 'deps']);

  if (result.exitCode == 65 || result.exitCode == 66) {
    throw PackageException(
        [PackageExceptionDetails._((result.stderr as String).trim())]);
  }

  if (result.exitCode != 0) {
    throw ProcessException(
        dartPath,
        ['pub', 'deps'],
        '***OUT***\n${result.stdout}\n***ERR***\n${result.stderr}\n***',
        exitCode);
  }
}

class PubspecLock {
  final YamlMap? _packages;

  PubspecLock(this._packages);

  static Future<PubspecLock> read({bool offline = false}) async {
    if (!offline) {
      await _runPubDeps();
    }
    var dir = p.absolute(p.current);
    while (true) {
      final candidate = p.join(
        dir,
        '.dart_tool',
        'package_config.json',
      );
      if (File(candidate).existsSync()) break;
      final next = p.dirname(dir);
      if (next == dir) {
        // Give up.
        dir = p.current;
        break;
      }
      dir = next;
    }

    final pubspecLock = loadYaml(
            await File(p.relative(p.join(dir, 'pubspec.lock'))).readAsString())
        as YamlMap;

    final packages = pubspecLock['packages'] as YamlMap?;
    return PubspecLock(packages);
  }

  List<PackageExceptionDetails> checkPackage(
      String pkgName, VersionConstraint constraint,
      {String? forArgument}) {
    final issues = <PackageExceptionDetails>[];
    final missingDetails =
        PackageExceptionDetails.missingDep(pkgName, constraint);

    final pkgDataMap =
        (_packages == null) ? null : _packages[pkgName] as YamlMap?;
    if (pkgDataMap == null) {
      issues.add(missingDetails);
    } else {
      final source = pkgDataMap['source'] as String?;
      if (source == 'hosted') {
        // NOTE: pkgDataMap['description'] should be:
        //           `{url: https://pub.dev, name: [pkgName]}`
        //       If a user is playing around here, they are on their own.

        final version = pkgDataMap['version'] as String;
        final pkgVersion = Version.parse(version);
        if (!constraint.allows(pkgVersion)) {
          final error = 'The `$pkgName` version – $pkgVersion – is not '
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
  final buildDaemonConstraint = '^4.0.0';

  final issues = <PackageExceptionDetails>[];

  final buildDaemonIssues = pubspecLock.checkPackage(
    'build_daemon',
    VersionConstraint.parse(buildDaemonConstraint),
  );

  // Only warn of build_daemon issues if they have a dependency on the package.
  if (buildDaemonIssues.any((issue) => !issue._missingDependency)) {
    final info = await _latestPackageInfo();
    final issuePreamble =
        'This version of webdev does not support the `build_daemon` '
        'protocol used by your version of `build_runner`.';
    // Check if the newer version supports the `build_daemon` transitive version
    // used by their application.
    if (info.isNewer &&
        pubspecLock
            .checkPackage('build_daemon', info.buildDaemonConstraint)
            .isEmpty) {
      issues.add(PackageExceptionDetails._('$issuePreamble\n'
          'A newer version of webdev is available which supports '
          'your version of the `build_daemon`. Please update.'));
    } else {
      issues.add(PackageExceptionDetails._('$issuePreamble\n'
          'Please add a dev dependency on `build_daemon` with constraint: '
          '$buildDaemonConstraint'));
    }
  }
  return issues;
}

final buildRunnerConstraint = VersionConstraint.parse('^2.4.0');
final buildWebCompilersConstraint = VersionConstraint.parse('^4.0.4');

// Note the minimum versions should never be dev versions as users will not
// get them by default.
Future<void> checkPubspecLock(PubspecLock pubspecLock,
    {required bool requireBuildWebCompilers}) async {
  final issues = <PackageExceptionDetails>[];
  final buildRunnerIssues =
      pubspecLock.checkPackage('build_runner', buildRunnerConstraint);

  issues.addAll(buildRunnerIssues);

  if (requireBuildWebCompilers) {
    issues.addAll(pubspecLock.checkPackage(
        'build_web_compilers', buildWebCompilersConstraint));
  }

  if (buildRunnerIssues.isEmpty) {
    issues.addAll(await _validateBuildDaemonVersion(pubspecLock));
  }

  if (issues.isNotEmpty) {
    throw PackageException(issues);
  }
}

class _PackageInfo {
  final Version? version;
  final VersionConstraint buildDaemonConstraint;
  final bool isNewer;
  _PackageInfo(this.version, this.buildDaemonConstraint, this.isNewer);
}

/// Returns the package info for the latest webdev release.
Future<_PackageInfo> _latestPackageInfo() async {
  final response = await get(Uri.parse('https://pub.dev/api/packages/webdev'),
      headers: {HttpHeaders.userAgentHeader: 'webdev $packageVersion'});
  final responseObj = json.decode(response.body);
  final pubspec = Pubspec.fromJson(
      responseObj['latest']['pubspec'] as Map<String, dynamic>);
  final buildDaemonDependency = pubspec.dependencies['build_daemon'];
  // This should never be satisfied.
  var buildDaemonConstraint = VersionConstraint.parse('0.0.0');
  if (buildDaemonDependency is HostedDependency) {
    buildDaemonConstraint = buildDaemonDependency.version;
  }
  final currentVersion = Version.parse(packageVersion);
  final pubspecVersion = pubspec.version;
  final isNewer = (pubspecVersion == null)
      ? true
      : currentVersion.compareTo(pubspecVersion) < 0;
  return _PackageInfo(pubspec.version, buildDaemonConstraint, isNewer);
}
