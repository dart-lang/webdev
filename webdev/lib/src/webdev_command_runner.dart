// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/command_runner.dart';

import 'command/build_command.dart';
import 'command/serve_command.dart';
import 'util.dart';

export 'pubspec.dart' show PackageException;

Future<int> run(List<String> args) async {
  var runner =
      new CommandRunner<int>(appName, 'A tool to develop Dart web projects.')
        ..addCommand(new BuildCommand())
        ..addCommand(new ServeCommand());

  // In the case of `help`, `null` is returned. Treat that as success.
  return await runner.run(args) ?? 0;
}
