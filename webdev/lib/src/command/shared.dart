// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:build_cli_annotations/build_cli_annotations.dart';
import 'package:meta/meta.dart';

import '../pubspec.dart';
import 'configuration.dart';

part 'shared.g.dart';

final lineLength = stdout.hasTerminal ? stdout.terminalColumns : 80;

void addSharedArgs(ArgParser argParser,
    {String outputDefault, bool releaseDefault}) {
  outputDefault ??= outputNone;
  releaseDefault ??= true;
  _$populateSharedOptionsParser(argParser,
      outputDefaultOverride: outputDefault,
      releaseDefaultOverride: releaseDefault);
}

SharedOptions parseSharedOptionsResult(ArgResults result) =>
    _$parseSharedOptionsResult(result);

List<String> buildRunnerArgs(
    PubspecLock pubspecLock, SharedOptions configuration) {
  var arguments = <String>[];
  if (configuration.release) {
    arguments.add('--$releaseFlag');
  }

  if (configuration.output != null && configuration.output != outputNone) {
    arguments.addAll(['--$outputFlag', configuration.output]);
  }

  if (configuration.verbose) {
    arguments.add('--$verboseFlag');
  }
  return arguments;
}

Future<PubspecLock> readPubspecLock(SharedOptions configuration,
    [String path]) async {
  var pubspecLock = await PubspecLock.read(path);
  await checkPubspecLock(pubspecLock,
      requireBuildWebCompilers: configuration.requireBuildWebCompilers);
  return pubspecLock;
}

@CliOptions()
class SharedOptions {
  @CliOption(
    name: outputFlag,
    abbr: 'o',
    provideDefaultToOverride: true,
    help: 'A directory to write the result of a build to. Or a mapping '
        'from a top-level directory in the package to the directory to '
        'write a filtered build output to. For example "web:deploy".\n'
        'A value of "NONE" indicates that no "--output" value should be '
        'passed to `build_runner`.',
  )
  final String output;

  @CliOption(
    name: releaseFlag,
    abbr: 'r',
    provideDefaultToOverride: true,
    negatable: true,
    help: 'Build with release mode defaults for builders.',
  )
  final bool release;

  @CliOption(
    name: requireBuildWebCompilersFlag,
    defaultsTo: true,
    negatable: true,
    help: 'If a dependency on `build_web_compilers` is required to run.',
  )
  final bool requireBuildWebCompilers;

  @CliOption(
    name: verboseFlag,
    abbr: 'v',
    defaultsTo: false,
    negatable: false,
    help: 'Enables verbose logging.',
  )
  final bool verbose;

  SharedOptions({
    @required this.release,
    @required this.verbose,
    @required this.requireBuildWebCompilers,
    @required this.output,
  });
}
