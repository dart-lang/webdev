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

void addSharedArgs(
  ArgParser argParser, {
  String? outputDefault,
  bool? releaseDefault,
}) {
  outputDefault ??= outputNone;
  releaseDefault ??= true;
  argParser
    ..addOption(
      outputFlag,
      abbr: 'o',
      defaultsTo: outputDefault,
      help:
          'A directory to write the result of a build to. Or a mapping '
          'from a top-level directory in the package to the directory to '
          'write a filtered build output to. For example "web:deploy".\n'
          'A value of "NONE" indicates that no "--output" value should be '
          'passed to `build_runner`.',
    )
    ..addOption(
      nullSafetyFlag,
      abbr: 'n',
      defaultsTo: nullSafetyAuto,
      allowed: [nullSafetySound, nullSafetyUnsound, nullSafetyAuto],
      help:
          'DEPRECATED: If "sound", `package:build_web_compilers` will be run '
          'with sound null safety support. '
          'If "unsound", `package:build_web_compilers` will be run without '
          'sound null safety support. '
          'If "auto", the default `package:build_web_compilers` '
          'behavior is used.',
      hide: true,
    )
    ..addFlag(
      releaseFlag,
      abbr: 'r',
      defaultsTo: releaseDefault,
      negatable: true,
      help: 'Build with release mode defaults for builders.',
    )
    ..addFlag(
      requireBuildWebCompilersFlag,
      defaultsTo: true,
      negatable: true,
      help: 'If a dependency on `build_web_compilers` is required to run.',
    )
    ..addFlag(
      disableDdsFlag,
      negatable: false,
      help:
          'Disable the Dart Development Service (DDS). Disabling DDS may '
          'result in a degraded developer experience in some tools.',
      hide: true,
    )
    ..addFlag(
      enableExpressionEvaluationFlag,
      abbr: 'e',
      defaultsTo: true,
      negatable: true,
      help: 'Enable expression evaluation features in the debugger.',
    )
    ..addMultiOption(
      enableExperimentOption,
      abbr: 'x',
      defaultsTo: null,
      hide: true,
      help: 'Enable experiment features in the debugger.',
    )
    ..addFlag(
      canaryFeaturesFlag,
      abbr: 'c',
      defaultsTo: false,
      negatable: true,
      hide: true,
      help: 'Enables DDC canary features.',
    )
    ..addFlag(
      verboseFlag,
      abbr: 'v',
      defaultsTo: false,
      negatable: false,
      help: 'Enables verbose logging.',
    )
    ..addFlag(
      offlineFlag,
      defaultsTo: false,
      negatable: false,
      help: 'Disable fetching from pub.dev.',
    );
}

/// Parses the provided [Configuration] to return a list of
/// `package:build_runner` appropriate arguments.
List<String> buildRunnerArgs(Configuration configuration) {
  final arguments = <String>[];
  if (configuration.release) {
    arguments.add('--$releaseFlag');
  }

  if (configuration.verbose) {
    arguments.add('--$verboseFlag');
  }

  if (configuration.enableExpressionEvaluation) {
    arguments
      ..add('--define')
      ..add('build_web_compilers|ddc=generate-full-dill=true');
  }

  for (final experiment in configuration.experiments) {
    arguments.add('--enable-experiment=$experiment');
  }

  if (configuration.canaryFeatures) {
    arguments
      ..add('--define')
      ..add('build_web_compilers|sdk_js=web-hot-reload=true');
    arguments
      ..add('--define')
      ..add('build_web_compilers|entrypoint=web-hot-reload=true');
    arguments
      ..add('--define')
      ..add('build_web_compilers|entrypoint_marker=web-hot-reload=true');
    arguments
      ..add('--define')
      ..add('build_web_compilers|ddc=web-hot-reload=true');
    arguments
      ..add('--define')
      ..add('build_web_compilers|ddc_modules=web-hot-reload=true');
  }

  return arguments;
}

Future<void> validatePubspecLock(Configuration configuration) async {
  final pubspecLock = await PubspecLock.read(offline: configuration.offline);
  await checkPubspecLock(
    pubspecLock,
    requireBuildWebCompilers: configuration.requireBuildWebCompilers,
  );
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
      '(such as `web` or `test`), but was given `$path`.',
    );
  }
}

final _defaultWebDirs = const ['web'];

/// Parses trailing arguments in `<dir>:<port>` format into a map of
/// directories to ports they are being served on.
///
/// Throws an [InvalidConfiguration] exception if it can't find at
/// least one directory.
Map<String, int> parseDirectoryArgs(List<String> args, {int? basePort}) {
  final result = <String, int>{};
  var port = basePort ?? 8080;
  if (args.isEmpty) {
    for (final dir in _defaultWebDirs) {
      if (Directory(dir).existsSync()) {
        result[dir] = port++;
      }
    }
  } else {
    for (final arg in args) {
      final splitOption = arg.split(':');
      ensureIsTopLevelDir(splitOption.first);
      if (splitOption.length == 2) {
        result[splitOption.first] = int.parse(splitOption.last);
      } else {
        result[arg] = port++;
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
  for (final app in launchApps) {
    final dir = p.url.split(app).first;
    if (!serveDirs.contains(dir)) {
      throw InvalidConfiguration(
        'Unable to launch app `$app` since its top level dir (`$dir`) '
        'is not being served. The currently directories being served are: '
        '${serveDirs.toList()}',
      );
    }
  }
}
