// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../pubspec.dart';
import 'configuration.dart';

final lineLength = stdout.hasTerminal ? stdout.terminalColumns : 80;

void addSharedArgs(ArgParser argParser,
    {String outputDefault, bool releaseDefault}) {
  outputDefault ??= outputNone;
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
    ..addFlag(requireBuildWebCompilersFlag,
        defaultsTo: true,
        negatable: true,
        help: 'If a dependency on `build_web_compilers` is required to run.')
    ..addFlag(verboseFlag,
        abbr: 'v',
        defaultsTo: false,
        negatable: false,
        help: 'Enables verbose logging.');
}

/// Parses the provided [Configuration] to return a list of
/// `package:build_runner` appropriate arguments.
List<String> buildRunnerArgs(
    PubspecLock pubspecLock, Configuration configuration) {
  var arguments = <String>[];
  if (configuration.release) {
    arguments.add('--$releaseFlag');
  }

  if (configuration.verbose) {
    arguments.add('--$verboseFlag');
  }
  return arguments;
}

Future<PubspecLock> readPubspecLock(Configuration configuration) async {
  var pubspecLock = await PubspecLock.read();
  await checkPubspecLock(pubspecLock,
      requireBuildWebCompilers: configuration.requireBuildWebCompilers);
  return pubspecLock;
}

/// Checks that the normalized form of [path] is a top level directory under
/// such as `web` or `test`.
///
/// If it is not then an [InvalidConfiguration] error will be thrown.
void ensureIsTopLevelDir(String path) {
  path = p.normalize(path);
  if (path.isEmpty ||
      path == '.' ||
      path == '..' ||
      path.contains(r'\') ||
      path.contains(r'/')) {
    throw InvalidConfiguration(
        'Only top level directories under the package can be built or served '
        '(such as `web` or `test`), but was given `$path`.');
  }
}

final _defaultWebDirs = const ['web'];

/// Parses trailing arguments in `<dir>:<port>` format into a map of
/// directories to ports they are being served on.
///
/// Throws an [InvalidConfiguration] exception if it can't find at
/// least one directory.
Map<String, int> parseDirectoryArgs(List<String> args, {int basePort}) {
  var result = <String, int>{};
  basePort ??= 8080;
  if (args.isEmpty) {
    for (var dir in _defaultWebDirs) {
      if (Directory(dir).existsSync()) {
        result[dir] = basePort++;
      }
    }
  } else {
    for (var arg in args) {
      var splitOption = arg.split(':');
      ensureIsTopLevelDir(splitOption.first);
      if (splitOption.length == 2) {
        result[splitOption.first] = int.parse(splitOption.last);
      } else {
        result[arg] = basePort++;
      }
    }
  }
  if (result.isEmpty) {
    throw InvalidConfiguration('''
Unable to detect a default directory to serve, by default $_defaultWebDirs is
supported.

You can specify a custom directory to serve by providing trailing arguments
in the `<directory>:<port>` format, such as `webdev serve test:8080`.
''');
  }
  return result;
}

void validateLaunchApps(List<String> launchApps, Iterable<String> serveDirs) {
  for (var app in launchApps) {
    var dir = p.url.split(app).first;
    if (!serveDirs.contains(dir)) {
      throw InvalidConfiguration(
          'Unable to launch app `$app` since its top level dir (`$dir`) '
          'is not being served. The currently directories being served are: '
          '${serveDirs.toList()}');
    }
  }
}
