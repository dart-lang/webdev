// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// INSTRUCTIONS:

// Builds the unminifed dart2js extension (see DDC issue:
// see DDC issue: https://github.com/dart-lang/sdk/issues/49869).

// Run from the extension root directory:
//    - For dev: dart run tool/build_extension.dart
//    - For prod: dart run tool/build_extension.dart prod

import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const prodFlag = 'prod';

void main(List<String> arguments) {
  exitCode = 0; // presume success
  final parser = ArgParser()
    ..addFlag(prodFlag, negatable: true, defaultsTo: false);
  final argResults = parser.parse(arguments);

  run(isProd: argResults[prodFlag] as bool);
}

Future<void> run({required bool isProd}) async {
  logInfo('Building extension for ${isProd ? 'prod' : 'dev'}');
  logInfo('Compiling extension with dart2js to /compiled directory');
  logOutput(
    await Process.run(
      'dart',
      ['run', 'build_runner', 'build', 'web', '--output', 'build', '--release'],
    ),
  );
  logInfo('Updating manifest.json in /compiled directory.');
  logOutput(
    await Process.run(
      'dart',
      [p.join('tool', 'update_dev_files.dart')],
    ),
  );
}

void logInfo(String message) {
  print('[BUILD STEP] $message');
}

void logOutput(ProcessResult result) {
  final output = result.stdout;
  final outputList = output is List ? output : [output ?? ''];
  print(outputList.map((output) => '$output').join('\n'));
}
