import 'package:args/command_runner.dart';

import 'command/build_command.dart';
import 'command/serve_command.dart';

/// All available top level commands.
CommandRunner webdevCommandRunner() =>
    new CommandRunner('webdev', 'A tool to develop Dart web projects.')
      ..addCommand(new BuildCommand())
      ..addCommand(new ServeCommand());
