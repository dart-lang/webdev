// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:pub_semver/pub_semver.dart';

import '../pubspec.dart';
import 'command_base.dart';

const _liveReload = 'live-reload';
const _hotReload = 'hot-reload';

/// Command to execute pub run build_runner serve.
class ServeCommand extends CommandBase {
  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that re-builds on changes.';

  @override
  String get invocation => '${super.invocation} [<directory>[:<port>]]...';

  ServeCommand() : super(releaseDefault: false, outputDefault: outputNone) {
    // TODO(nshahan) Expose more args passed to build_runner serve.
    // build_runner might expose args for use in wrapping scripts like this one.
    argParser
      ..addOption('hostname',
          help: 'Specify the hostname to serve on', defaultsTo: 'localhost')
      ..addFlag('log-requests',
          defaultsTo: false,
          negatable: false,
          help: 'Enables logging for each request to the server.')
      ..addFlag(_liveReload,
          defaultsTo: false,
          negatable: false,
          help: 'Automatically refreshes the page after each build.\n'
              "Can't be used together with --$_hotReload.")
      ..addFlag(_hotReload,
          defaultsTo: false,
          negatable: false,
          help: 'Automatically reloads changed modules after each build.\n'
              'See https://github.com/dart-lang/build/blob/master/docs/hot_module_reloading.md for more info.\n'
              "Can't be used together with --$_liveReload.");
  }

  @override
  List<String> getArgs(PubspecLock pubspecLock) {
    var arguments = super.getArgs(pubspecLock);

    var hostname = argResults['hostname'] as String;
    if (hostname != null) {
      arguments.addAll(['--hostname', hostname]);
    }

    if (argResults['log-requests'] == true) {
      arguments.add('--log-requests');
    }

    if (argResults[_liveReload] as bool && argResults[_hotReload] as bool) {
      throw UsageException(
          'Options --$_liveReload and --$_hotReload '
          "can't both be used together",
          usage);
    } else if (argResults[_liveReload] as bool) {
      var issues = pubspecLock.checkPackage(
          'build_runner', new VersionConstraint.parse('>=0.10.1'));
      issues.addAll(pubspecLock.checkPackage('build_web_compilers',
          new VersionConstraint.parse('>=0.4.2 <2.0.0')));
      if (issues.isEmpty) {
        arguments.add('--$_liveReload');
      } else {
        throw new PackageException(issues, unsupportedArgument: _liveReload);
      }
    } else if (argResults[_hotReload] as bool) {
      var issues = pubspecLock.checkPackage(
          'build_runner', new VersionConstraint.parse('>=0.10.2'));
      issues.addAll(pubspecLock.checkPackage('build_web_compilers',
          new VersionConstraint.parse('>=0.4.3 <2.0.0')));
      if (issues.isEmpty) {
        arguments.add('--$_hotReload');
      } else {
        throw new PackageException(issues, unsupportedArgument: _hotReload);
      }
    }

    // The remaining arguments should be interpreted as [<directory>[:<port>]].
    arguments.addAll(argResults.rest);

    return arguments;
  }

  @override
  Future<int> run() => runCore('serve');
}
