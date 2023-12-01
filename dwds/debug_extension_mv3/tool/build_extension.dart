// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// INSTRUCTIONS:

// Builds the unminified dart2js extension (see DDC issue:
// https://github.com/dart-lang/sdk/issues/49869).

// Run from the extension root directory:
//    - For dev: dart run tool/build_extension.dart
//    - For prod: dart run tool/build_extension.dart --prod
//    - For MV2: dart run tool/build_extension.dart --mv2

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const _prodFlag = 'prod';
const _mv2Flag = 'mv2';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(_prodFlag, negatable: true, defaultsTo: false)
    ..addFlag(_mv2Flag, negatable: true, defaultsTo: false);
  final argResults = parser.parse(arguments);

  exitCode = await run(
    isProd: argResults[_prodFlag] as bool,
    isMV2: argResults[_mv2Flag] as bool,
  );
  if (exitCode != 0) {
    _logWarning('Run terminated unexpectedly with exit code: $exitCode');
  }
}

Future<int> run({required bool isProd, required bool isMV2}) async {
  _logInfo(
    'Building ${isMV2 ? 'MV2' : 'MV3'} extension for ${isProd ? 'prod' : 'dev'}',
  );
  _logInfo('Compiling extension with dart2js to /compiled directory');
  final compileStep = await Process.start(
    'dart',
    ['run', 'build_runner', 'build', 'web', '--output', 'build', '--release'],
  );
  final compileExitCode = await _handleProcess(compileStep);
  // Terminate early if compilation failed:
  if (compileExitCode != 0) {
    return compileExitCode;
  }
  final manifestFileName = isMV2 ? 'manifest_mv2' : 'manifest_mv3';
  _logInfo('Copying manifest.json to /compiled directory');
  try {
    File(p.join('web', '$manifestFileName.json')).copySync(
      p.join('compiled', 'manifest.json'),
    );
  } catch (error) {
    _logWarning('Copying manifest file failed: $error');
    // Return non-zero exit code to indicate failure:
    return 1;
  }
  // If we're compiling for prod, skip updating the manifest.json:
  if (isProd) return 0;
  // Update manifest.json for dev:
  _logInfo('Updating manifest.json in /compiled directory.');
  final updateStep = await Process.start(
    'dart',
    [p.join('tool', 'update_dev_files.dart')],
  );
  final updateExitCode = await _handleProcess(updateStep);
  // Return exit code (0 indicates success):
  return updateExitCode;
}

Future<int> _handleProcess(Process process) {
  _handleOutput(process.stdout, isStdout: true);
  _handleOutput(process.stderr, isStdout: false);
  return process.exitCode;
}

void _handleOutput(Stream<List<int>> output, {bool isStdout = true}) {
  output
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => _handleOutputLine(line, isStdout: isStdout));
}

void _handleOutputLine(String line, {bool isStdout = true}) {
  // Skip empty lines:
  if (line.isEmpty) return;
  // Log any unexpected errors and throw:
  final outputName = isStdout ? 'stdout' : 'stderr';
  if (line.toUpperCase().contains('SEVERE') ||
      line.toUpperCase().contains('ERROR')) {
    final error = 'Unexpected error in $outputName: $line';
    _logWarning(error);
    throw Exception(error);
  }
  // Log message to the terminal:
  final message = '$outputName: $line';
  isStdout ? _logInfo(message) : _logWarning(message);
}

void _logInfo(String message) {
  stdout.writeln(message);
}

void _logWarning(String warning) {
  stderr.writeln(warning);
}
