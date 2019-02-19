// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/args.dart';

import '../pubspec.dart';

const outputFlag = 'output';
const releaseFlag = 'release';
const verboseFlag = 'verbose';
const _outputNone = 'NONE';
const _requireBuildWebCompilers = 'build-web-compilers';

void addSharedArgs(ArgParser argParser,
    {String outputDefault, bool releaseDefault}) {
  outputDefault ??= _outputNone;
  releaseDefault ??= true;
  argParser
    ..addOption(
      outputFlag,
      abbr: 'o',
      defaultsTo: outputDefault,
      help: 'A directory to write the result of a build to. Or a mapping '
          'from a top-level directory in the package to the directory to '
          'write a filtered build output to. For example "web:deploy".\n'
          'A value of "NONE" indicates that no "--output" value should be '
          'passed to `build_runner`.',
    )
    ..addFlag(releaseFlag,
        abbr: 'r',
        defaultsTo: releaseDefault,
        negatable: true,
        help: 'Build with release mode defaults for builders.')
    ..addFlag(_requireBuildWebCompilers,
        defaultsTo: true,
        negatable: true,
        help: 'If a dependency on `build_web_compilers` is required to run.')
    ..addFlag(verboseFlag,
        abbr: 'v',
        defaultsTo: false,
        negatable: false,
        help: 'Enables verbose logging.');
}

List<String> buildRunnerArgs(PubspecLock pubspecLock, ArgResults argResults) {
  var arguments = <String>[];
  if (argResults[releaseFlag] as bool) {
    arguments.add('--$releaseFlag');
  }

  var output = argResults[outputFlag] as String;
  if (output != null && output != _outputNone) {
    arguments.addAll(['--$outputFlag', output]);
  }

  if (argResults[verboseFlag] as bool) {
    arguments.add('--$verboseFlag');
  }
  return arguments;
}

Future<PubspecLock> readPubspecLock(ArgResults argResults,
    [String path]) async {
  var pubspecLock = await PubspecLock.read(path);
  await checkPubspecLock(pubspecLock,
      requireBuildWebCompilers: argResults[_requireBuildWebCompilers] as bool);
  return pubspecLock;
}
