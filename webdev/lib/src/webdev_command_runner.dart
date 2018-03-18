// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:args/command_runner.dart';

import 'command/build_command.dart';
import 'command/serve_command.dart';

/// All available top level commands.
CommandRunner webdevCommandRunner() =>
    new CommandRunner('webdev', 'A tool to develop Dart web projects.')
      ..addCommand(new BuildCommand())
      ..addCommand(new ServeCommand());
