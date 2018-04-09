// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'command_base.dart';

const _requireBuildWebCompilers = 'require-build-web-compilers';

/// Command to execute pub run build_runner serve.
class ServeCommand extends CommandBase {
  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that re-builds on changes.';

  @override
  String get invocation => '${super.invocation} [<directory>[:<port>]]...';

  ServeCommand() : super(releaseDefault: false) {
    // TODO(nshahan) Expose more args passed to build_runner serve.
    // build_runner might expose args for use in wrapping scripts like this one.
    argParser
      ..addOption('hostname',
          help: 'Specify the hostname to serve on', defaultsTo: 'localhost')
      ..addFlag('log-requests',
          defaultsTo: false,
          negatable: false,
          help: 'Enables logging for each request to the server.')
      ..addFlag(_requireBuildWebCompilers,
          defaultsTo: true,
          negatable: true,
          help: 'If a dependency on `build_web_compilers` is required to run.');
  }

  @override
  List<String> getArgs() {
    var arguments = super.getArgs();

    var hostname = argResults['hostname'] as String;
    if (hostname != null) {
      arguments.addAll(['--hostname', hostname]);
    }

    if (argResults['log-requests'] == true) {
      arguments.add('--log-requests');
    }

    return arguments;
  }

  @override
  Future<int> run() => runCore('serve',
      requireBuildWebCompilers: argResults[_requireBuildWebCompilers] as bool);
}
