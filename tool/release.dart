// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';

const _packageOption = 'package';
const _versionOption = 'version';
const _resetFlag = 'reset';
const _skipStableCheckFlag = 'skipStableCheck';

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
    _logWarning('Please specify package with either --p=dwds or --p=webdev');
    return;
  }

  final isReset = argResults[_resetFlag] as bool?;
  final newVersion = argResults[_versionOption] as String?;
  final skipStableCheck = argResults[_skipStableCheckFlag] as bool?;

  int exitCode;
  if (isReset == true) {
    exitCode = runReset(
      package: package,
      newVersion: newVersion,
    );
  } else {
    exitCode = await runRelease(
      package: package,
      newVersion: newVersion,
      skipStableCheck: skipStableCheck,
    );
  }
  if (exitCode != 0) {
    _logWarning('Run terminated unexpectedly with exit code: $exitCode');
  }
}

int runReset({
  required String package,
  String? newVersion,
}) {
  // Check that a new dev version has been provided.
  final currentVersion = _readVersionFile(package);
  if (newVersion == null || !newVersion.contains('dev')) {
    _logInfo(
      '''
      Please provide the next dev version for $package, e.g. -v 3.0.1-dev
      Current version is $currentVersion.
    ''',
    );
    return 1;
  }

  // Update the version strings in CHANGELOG and pubspec.yaml.
  _updateVersionStrings(
    package,
    currentVersion: currentVersion,
    nextVersion: newVersion,
    isReset: true,
  );

  return 0;
}

Future<int> runRelease({
  required String package,
  String? newVersion,
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

  // Update the pinned version of DWDS for webdev releases.
  if (package == 'webdev') {
    _logInfo('Updating pinned version of DWDS.');
    await _updateDwdsPin(package);
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
  final nextVersion = newVersion ?? _removeDev(currentVersion);
  _updateVersionStrings(
    package,
    currentVersion: currentVersion,
    nextVersion: nextVersion,
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

void _updateVersionStrings(
  String package, {
  required String nextVersion,
  required String currentVersion,
  bool isReset = false,
}) {
  _logInfo('Updating $package from $currentVersion to $nextVersion');
  final pubspec = File('../$package/pubspec.yaml');
  final changelog = File('../$package/CHANGELOG.md');
  if (isReset) {
    _addNewLine(changelog, newLine: '## $nextVersion');
    _replaceInFile(pubspec, query: currentVersion, replaceWith: nextVersion);
  } else {
    for (final file in [pubspec, changelog]) {
      _replaceInFile(file, query: currentVersion, replaceWith: nextVersion);
    }
  }
}

void _addNewLine(
  File file, {
  required String newLine,
}) {
  final newLines = [newLine, '', ...file.readAsLinesSync()];
  final content = newLines.joinWithNewLine();
  return file.writeAsStringSync(content);
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
