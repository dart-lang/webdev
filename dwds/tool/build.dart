// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

void main() async {
  // 1. Extract the version from pubspec.yaml
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final versionMatch = RegExp(r'version: (.*)').firstMatch(pubspec);
  final version = versionMatch?.group(1);
  if (version == null) {
    throw Exception('Failed to find version in pubspec.yaml');
  }

  // 2. Generate lib/src/version.dart
  final versionFile = File('lib/src/version.dart');
  versionFile.writeAsStringSync('''
// Generated code. Do not modify.
const packageVersion = '$version';
''');

  // 3. Compile the web client to JavaScript
  print('Compiling client.js...');
  final result = await Process.run('dart', [
    'compile',
    'js',
    '-O1',
    '--no-source-maps',
    '-o',
    'lib/src/injected/client.js',
    'web/client.dart',
  ]);

  if (result.exitCode != 0) {
    print('Failed to compile client.js');
    print(result.stdout);
    print(result.stderr);
    exit(result.exitCode);
  }

  print('Compilation successful');

  // 4. Clean up the generated .deps file
  final depsFile = File('lib/src/injected/client.js.deps');
  if (depsFile.existsSync()) {
    depsFile.deleteSync();
  }
}
