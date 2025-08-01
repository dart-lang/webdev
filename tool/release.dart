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
///  `dart run release.dart --reset -p dwds -v [[wip version]]`
///
/// To reset WebDev after a release:
///   `dart run release.dart --reset -p webdev -v [[wip version]]`

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(_packageOption, abbr: 'p', allowed: ['webdev', 'dwds'])
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
    exitCode = await runReset(package: package, newVersion: newVersion);
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

Future<int> runReset({required String package, String? newVersion}) {
  // Check that a new wip version has been provided.
  final currentVersion = _readVersionFile(package);
  if (newVersion == null || !newVersion.contains('wip')) {
    _logInfo('''
      Please provide the next wip version for $package, e.g. -v 3.0.1-wip
      Current version is $currentVersion.
    ''');
    return Future.value(1);
  }

  // Reset the dependency overrides for the package:
  _updateOverrides(package, includeOverrides: true);

  // Update the version strings in CHANGELOG and pubspec.yaml.
  _updateVersionStrings(
    package,
    currentVersion: currentVersion,
    nextVersion: newVersion,
    isReset: true,
  );

  // Build the package.
  final exitCode = _buildPackage(package);
  return exitCode;
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
      _logWarning('''
        Expected to be on stable version of Dart, instead on:
        $versionInfo
        To skip this check, re-run with --skipStableCheck
        ''');
      return checkVersionProcess.exitCode;
    }
  }

  // Update the pinned version of DWDS for webdev releases.
  if (package == 'webdev') {
    final newVersion = await _updateDwdsPin('webdev');
    _logInfo('Add pinned DWDS info to CHANGELOG.');
    final changelog = File('../webdev/CHANGELOG.md');
    _addNewLine(
      changelog,
      newLine: '- Update `dwds` constraint to `${newVersion ?? 'TODO'}`.',
      insertAt: 2,
    );
  }

  // Remove any dependency overrides for the package:
  _logInfo('Removing dependency overrides for $package.');
  _updateOverrides(package, includeOverrides: false);

  // Run dart pub upgrade.
  for (final packagePath in [
    '../dwds',
    '../webdev',
    '../frontend_server_common',
    '../frontend_server_client',
    '../test_common',
  ]) {
    _logInfo('Upgrading pub packages for $packagePath');
    final pubUpgradeProcess = await Process.run('dart', [
      'pub',
      'upgrade',
    ], workingDirectory: packagePath);
    final upgradeErrors = pubUpgradeProcess.stderr as String;
    if (upgradeErrors.isNotEmpty) {
      _logWarning(upgradeErrors);
      return pubUpgradeProcess.exitCode;
    }
  }

  // Update the version strings in CHANGELOG and pubspec.yaml.
  final currentVersion = _readVersionFile(package);
  final nextVersion = newVersion ?? _removeWip(currentVersion);
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
  final buildProcess = await Process.run('dart', [
    'run',
    'build_runner',
    'build',
  ], workingDirectory: '../$package');

  final buildErrors = buildProcess.stderr as String;
  if (buildErrors.isNotEmpty) {
    _logWarning(buildErrors);
  }
  return buildProcess.exitCode;
}

void _updateOverrides(String package, {required bool includeOverrides}) {
  final overridesFilePath = '../$package/pubspec_overrides.yaml';
  final noOverridesFilePath = '../$package/ignore_pubspec_overrides.yaml';
  if (includeOverrides) {
    _renameFile(currentName: noOverridesFilePath, newName: overridesFilePath);
  } else {
    _renameFile(currentName: overridesFilePath, newName: noOverridesFilePath);
  }
}

void _renameFile({required String currentName, required String newName}) {
  final currentFile = File(currentName);
  if (!currentFile.existsSync()) {
    _logInfo('Skip renaming $currentName to $newName, file does not exist.');
    return;
  }
  currentFile.rename(newName);
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

void _addNewLine(File file, {required String newLine, int insertAt = 0}) {
  final currentLines = file.readAsLinesSync();
  final linesBefore = currentLines.sublist(0, insertAt);
  final linesAfter = currentLines.sublist(insertAt);
  final newLines = [...linesBefore, newLine, '', ...linesAfter];
  final content = newLines.joinWithNewLine();
  return file.writeAsStringSync(content);
}

bool _replaceInFile(
  File file, {
  required String query,
  required String replaceWith,
}) {
  final newLines = <String>[];
  var replaced = false;
  for (final line in file.readAsLinesSync()) {
    if (line.contains(query)) {
      newLines.add(line.replaceAll(query, replaceWith));
      replaced = true;
    } else {
      newLines.add(line);
    }
  }
  final content = newLines.joinWithNewLine();
  file.writeAsStringSync(content);
  return replaced;
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

String _removeWip(String wipVersion) {
  if (!wipVersion.contains('wip')) {
    throw Exception('$wipVersion is not a wip version.');
  }
  return wipVersion.split('-wip').first;
}

/// Returns the new pinned DWDS version on success.
Future<String?> _updateDwdsPin(String package) async {
  final pubOutdatedProcess = await Process.run('dart', [
    'pub',
    'outdated',
    '--no-dependency-overrides',
  ], workingDirectory: '../$package');
  final lines = pubOutdatedProcess.stdout.split('\n') as List<String>;
  String? nextDwdsVersion;
  String? currentDwdsVersion;
  for (final line in lines) {
    if (line.trim().startsWith('dwds')) {
      final segments = line
          .trim()
          .split(' ')
          .where((segment) => segment != ' ');
      nextDwdsVersion = segments.last;
      currentDwdsVersion = segments
          .lastWhere((segment) => segment.startsWith('*'))
          .substring(1);
      break;
    }
  }
  final next = nextDwdsVersion ?? '';
  final current = currentDwdsVersion ?? '';
  if (next.isNotEmpty && current.isNotEmpty) {
    _logInfo('Changing DWDS pin from $current to $next');
    _replaceInFile(
      File('../$package/pubspec.yaml'),
      query: current,
      replaceWith: next,
    );
    return nextDwdsVersion;
  }
  _logWarning('Unable to determine DWDS version to pin.');
  return null;
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
