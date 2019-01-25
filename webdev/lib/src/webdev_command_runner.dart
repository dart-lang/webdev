// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'command/build_command.dart';
import 'command/serve2_command.dart';
import 'command/serve_command.dart';
import 'util.dart';
import 'version.dart';

export 'pubspec.dart' show PackageException;
export 'util.dart' show appName;

Future<int> run(List<String> args) => _CommandRunner().run(args);

class _CommandRunner extends CommandRunner<int> {
  _CommandRunner() : super(appName, 'A tool to develop Dart web projects.') {
    argParser.addFlag('version',
        negatable: false, help: 'Prints the version of webdev.');
    addCommand(new BuildCommand());
    addCommand(new ServeCommand());
    addCommand(new Serve2Command());
  }

  @override
  Future<int> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['version'] as bool) {
      print(packageVersion);
      return 0;
    }

    // In the case of `help`, `null` is returned. Treat that as success.
    return await super.runCommand(topLevelResults) ?? 0;
  }
}
