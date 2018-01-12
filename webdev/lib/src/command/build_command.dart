import 'dart:async';

import 'package:io/io.dart';

import 'build_runner_command_base.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends BuildRunnerCommandBase {
  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  @override
  Future run() async {
    final manager = new ProcessManager();
    final executable = 'pub';
    final arguments = ['run', 'build_runner', 'build', '--assume-tty'];
    arguments.addAll(argResults.arguments);
    var spawn = await manager.spawn(executable, arguments);

    await spawn.exitCode;
    await sharedStdIn.terminate();
  }
}
