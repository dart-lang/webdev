// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';

/// Note: Must be run from the /tool directory.
///
/// To prepare DWDS for release:
///  `dart run release.dart -p dwds`
///
/// To prepare WebDev for release:
///  `dart run release.dart -p webdev`
///
/// To reset DWDS after a release:
///  `dart run release.dart --reset -p dwds -v -[[dev version]]`
///
/// To reset WebDev after a release:
///   `dart run release.dart --reset -p webdev -v -[[dev version]]`

const _packageOption = 'package';
const _versionOption = 'version';
const _resetFlag = 'reset';
const _skipStableCheckFlag = 'skipStableCheck';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      _packageOption,
      abbr: 'p',
      allowed: [
        'webdev',
        'dwds',
      ],
    )
    ..addOption(_versionOption, abbr: 'v')
    ..addFlag(_resetFlag, abbr: 'r')
    ..addFlag(_skipStableCheckFlag, abbr: 's');

  final argResults = parser.parse(arguments);
  final package = argResults[_packageOption] as String?;
  if (package == null) {
    _logWarning('Please specify package with either -p dwds or -p webdev');
    return;
  }

  final isReset = argResults[_resetFlag] as bool?;
  final nextVersion = argResults[_versionOption] as String?;
  final skipStableCheck = argResults[_skipStableCheckFlag] as bool?;

  int exitCode;
  if (isReset == true) {
    exitCode = await runReset(
      package: package,
      nextVersion: nextVersion,
    );
  } else {
    exitCode = await runRelease(
      package: package,
      nextVersion: nextVersion,
      skipStableCheck: skipStableCheck,
    );
  }
  if (exitCode != 0) {
    _logWarning('Run terminated unexpectedly with exit code: $exitCode');
  }
}

Future<int> runReset({
  required String package,
  String? nextVersion,
}) async {
  // Check that a new dev version has been provided.
  final currentVersion = _readVersionFile(package);
  if (nextVersion == null || !nextVersion.contains('dev')) {
    _logInfo(
      '''
      Please provide the next dev version for $package, e.g. -v 3.0.1-dev
      Current version is $currentVersion.
    ''',
    );
    return Future.value(1);
  }

  // Add the dependency overrides of DWDS back for webdev:
  if (package == 'webdev') {
    _logInfo('Adding back dependency overrides for DWDS.');
    _updateOverrides('webdev', includeOverrides: true);
    _updateOverrides('test_common', includeOverrides: true);
  }

  // Update the version strings in CHANGELOG and pubspec.yaml.
  await _updatePubspecAndChangelog(
    package,
    currentVersion: currentVersion,
    nextVersion: nextVersion,
    isReset: true,
  );

  // Build the package.
  final exitCode = _buildPackage(package);
  return exitCode;
}

Future<int> runRelease({
  required String package,
  String? nextVersion,
  bool? skipStableCheck,
}) async {
  // Check that we are on a stable version of Dart.
  if (skipStableCheck != true) {
    final checkVersionProcess = await Process.run('dart', ['--version']);
    final versionInfo = checkVersionProcess.stdout as String;
    if (!versionInfo.contains('stable')) {
      _logWarning(
        '''
        Expected to be on stable version of Dart, instead on:
        $versionInfo
        To skip this check, re-run with --skipStableCheck
        ''',
      );
      return checkVersionProcess.exitCode;
    }
  }

  if (package == 'webdev') {
    // Update the pinned version of DWDS for webdev releases.
    _logInfo('Updating pinned version of DWDS.');
    await _updateDwdsPin('webdev');
    await _updateDwdsPin('test_common');
    // Remove the dependency overrides of DWDS for webdev releases:
    _logInfo('Removing dependency overrides of DWDS.');
    _updateOverrides('webdev', includeOverrides: false);
    _updateOverrides('test_common', includeOverrides: false);
  }

  // Run dart pub upgrade.
  for (final packagePath in [
    '../dwds',
    '../webdev',
    '../frontend_server_common',
    '../frontend_server_client',
    '../test_common',
  ]) {
    _logInfo('Upgrading pub packages for $packagePath');
    final pubUpgradeProcess = await Process.run(
      'dart',
      [
        'pub',
        'upgrade',
      ],
      workingDirectory: packagePath,
    );
    final upgradeErrors = pubUpgradeProcess.stderr as String;
    if (upgradeErrors.isNotEmpty) {
      _logWarning(upgradeErrors);
      return pubUpgradeProcess.exitCode;
    }
  }

  // Update the version strings in CHANGELOG and pubspec.yaml.
  final currentVersion = _readVersionFile(package);
  await _updatePubspecAndChangelog(
    package,
    currentVersion: currentVersion,
    nextVersion: nextVersion ?? _removeDev(currentVersion),
    isReset: false,
  );

  // Build the package.
  final exitCode = _buildPackage(package);
  return exitCode;
}

Future<int> _buildPackage(String package) async {
  _logInfo('Building $package');
  final buildProcess = await Process.run(
    'dart',
    ['run', 'build_runner', 'build'],
    workingDirectory: '../$package',
  );

  final buildErrors = buildProcess.stderr as String;
  if (buildErrors.isNotEmpty) {
    _logWarning(buildErrors);
  }
  return buildProcess.exitCode;
}

void _updateOverrides(
  String package, {
  required bool includeOverrides,
}) {
  final overridesFilePath = '../$package/pubspec_overrides.yaml';
  final noOverridesFilePath = '../$package/ignore_pubspec_overrides.yaml';
  if (includeOverrides) {
    File(noOverridesFilePath).rename(overridesFilePath);
  } else {
    File(overridesFilePath).rename(noOverridesFilePath);
  }
}

Future<void> _updatePubspecAndChangelog(
  String package, {
  required String currentVersion,
  required String nextVersion,
  required bool isReset,
}) async {
  // Update the version in pubspec.yaml.
  _updatePubspecVersion(
    package,
    currentVersion: currentVersion,
    nextVersion: nextVersion,
  );

  // Populate the CHANGELOG:
  await _runChangelogGenerator(
    package,
    currentVersion: currentVersion,
    nextVersion: nextVersion,
    isReset: isReset,
  );
}

void _updatePubspecVersion(
  String package, {
  required String nextVersion,
  required String currentVersion,
}) {
  _logInfo('Updating $package from $currentVersion to $nextVersion');
  final pubspec = File('../$package/pubspec.yaml');
  _replaceInFile(pubspec, query: currentVersion, replaceWith: nextVersion);
}

Future<int> _runChangelogGenerator(
  String package, {
  required String nextVersion,
  required String currentVersion,
  required bool isReset,
}) async {
  _logInfo('Running the CHANGELOG generator for $package');
  final generateChangelogProcess = await Process.run(
    'dart',
    [
      'run',
      'generate_changelog.dart',
      '-n',
      nextVersion,
      '-c',
      currentVersion,
      if (isReset) '--reset',
    ],
  );

  final generateChangelogErrors = generateChangelogProcess.stderr as String;
  if (generateChangelogErrors.isNotEmpty) {
    _logWarning(generateChangelogErrors);
  }
  return generateChangelogProcess.exitCode;
}

void _replaceInFile(
  File file, {
  required String query,
  required String replaceWith,
}) {
  final newLines = <String>[];
  for (final line in file.readAsLinesSync()) {
    if (line.contains(query)) {
      newLines.add(line.replaceAll(query, replaceWith));
    } else {
      newLines.add(line);
    }
  }
  final content = newLines.joinWithNewLine();
  return file.writeAsStringSync(content);
}

String _readVersionFile(String package) {
  final versionFile = File('../$package/lib/src/version.dart');
  final lines = versionFile.readAsLinesSync();
  for (final line in lines) {
    if (line.startsWith('const packageVersion =')) {
      final version = line
          .split('=')
          .last
          .split('')
          .where((char) => char != ';' && char != "'" && char != '"')
          .join('');
      return version.trim();
    }
  }
  throw Exception('Could not read version in $package/lib/src/version.dart');
}

String _removeDev(String devVersion) {
  if (!devVersion.contains('dev')) {
    throw Exception('$devVersion is not a dev version.');
  }
  return devVersion.split('-dev').first;
}

Future<void> _updateDwdsPin(String package) async {
  final pubOutdatedProcess = await Process.run(
    'dart',
    [
      'pub',
      'outdated',
      '--no-dependency-overrides',
    ],
    workingDirectory: '../$package',
  );
  final lines = pubOutdatedProcess.stdout.split('\n') as List<String>;
  for (final line in lines) {
    if (line.trim().startsWith('dwds')) {
      final segments =
          line.trim().split(' ').where((segment) => segment != ' ');
      final nextVersion = segments.last;
      final currentVersion =
          segments.lastWhere((segment) => segment.startsWith('*')).substring(1);
      _logInfo('Changing DWDS pin from $currentVersion to $nextVersion');
      _replaceInFile(
        File('../$package/pubspec.yaml'),
        query: currentVersion,
        replaceWith: nextVersion,
      );
    }
  }
}

void _logInfo(String message) {
  stdout.writeln(message);
}

void _logWarning(String warning) {
  stderr.writeln(warning);
}

extension JoinExtension on List<String> {
  String joinWithNewLine() {
    return '${join('\n')}\n';
  }
}
