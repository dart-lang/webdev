import 'package:args/command_runner.dart';

import 'command/build_command.dart';

/// All available top level commands.
CommandRunner webdevCommandRunner() {
  final commandRunner =
      new CommandRunner('webdev', 'A tool to develop Dart web projects.');

  commandRunner.addCommand(new BuildCommand());

  return commandRunner;
}
