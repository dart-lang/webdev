// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';

const _versionOption = 'version';

void main(List<String> arguments) async {
  final parser = ArgParser()..addOption(_versionOption, abbr: 'v');
  final argResults = parser.parse(arguments);

  _readVersionFile();

  exitCode = await run(
    newVersion: argResults[_versionOption] as String?,
  );
  if (exitCode != 0) {
    print('Run terminated unexpectedly with exit code: $exitCode');
  }
}

Future<int> run({String? newVersion}) async {
  final currentVersion = _readVersionFile();
  final nextVersion = newVersion ?? _removeDev(currentVersion);
  print('Updating DWDS from $currentVersion to $nextVersion');
  for (var fileName in [
    'pubspec.yaml',
    'CHANGELOG.md',
  ]) {
    _replaceInFile(
      File(fileName),
      query: currentVersion,
      replaceWith: nextVersion,
    );
  }

  // Return exit code (0 indicates success):
  return 0;
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
