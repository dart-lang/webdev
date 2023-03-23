// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';

const _versionOption = 'version';
const _skipStableCheckFlag = 'skipStableCheck';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(_versionOption, abbr: 'v')
    ..addFlag(_skipStableCheckFlag, abbr: 's');
  final argResults = parser.parse(arguments);

  _readVersionFile();

  exitCode = await run(
    newVersion: argResults[_versionOption] as String?,
    skipStableCheck: argResults[_skipStableCheckFlag] as bool?,
  );
  if (exitCode != 0) {
    print('Run terminated unexpectedly with exit code: $exitCode');
  }
}

Future<int> run({String? newVersion, bool? skipStableCheck}) async {
  if (skipStableCheck != true) {
    final checkVersionProcess = await Process.run('dart', ['--version']);
    final versionInfo = checkVersionProcess.stdout;
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

  for (final packagePath in [
    './',
    '../webdev',
    '../frontend_server_common',
    '../frontend_server_client',
  ]) {
    _logInfo('Upgrading pub packages for $packagePath...');
    final pubUpgradeProcess = await Process.run(
      'dart',
      [
        'pub',
        'upgrade',
      ],
      workingDirectory: packagePath,
    );
    final upgradeErrors = pubUpgradeProcess.stderr ?? '';
    if (upgradeErrors.isNotEmpty) {
      _logWarning(upgradeErrors);
      return pubUpgradeProcess.exitCode;
    }
  }

  final currentVersion = _readVersionFile();
  final nextVersion = newVersion ?? _removeDev(currentVersion);
  _logInfo('Updating DWDS from $currentVersion to $nextVersion...');
  for (final fileName in [
    'pubspec.yaml',
    'CHANGELOG.md',
  ]) {
    _replaceInFile(
      File(fileName),
      query: currentVersion,
      replaceWith: nextVersion,
    );
  }

  _logInfo('Building DWDS...');
  final buildProcess = await Process.run(
    'dart',
    ['run', 'build_runner', 'build'],
  );

  final buildErrors = buildProcess.stderr ?? '';
  if (buildErrors.isNotEmpty) {
    _logWarning(buildErrors);
  }
  return buildProcess.exitCode;
}

void _replaceInFile(
  File file, {
  required String query,
  required String replaceWith,
}) {
  final newLines = [];
  for (final line in file.readAsLinesSync()) {
    if (line.contains(query)) {
      newLines.add(line.replaceAll(query, replaceWith));
    } else {
      newLines.add(line);
    }
  }
  final content = newLines.join('\n');
  return file.writeAsStringSync(content);
}

String _readVersionFile() {
  final versionFile = File('lib/src/version.dart');
  final lines = versionFile.readAsLinesSync();
  for (final line in lines) {
    if (line.startsWith('const packageVersion =')) {
      final version = line
          .split('=')
          .last
          .split('')
          .where((char) => char != ";" && char != "'" && char != '"')
          .join('');
      return version;
    }
  }
  throw Exception('Could not read version in lib/src/version.dart');
}

String _removeDev(String devVersion) {
  if (!devVersion.contains('dev')) {
    throw Exception('$devVersion is not a dev version.');
  }
  return devVersion.split('-dev').first;
}

void _logInfo(String message) {
  stdout.writeln(message);
}

void _logWarning(String warning) {
  stderr.writeln(warning);
}
