import 'dart:async';

import 'build_runner_command_base.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends BuildRunnerCommandBase {
  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  @override
  Future run() async {
    final arguments = ['build'];
    arguments.addAll(argResults.arguments);
    await runBuildRunner(arguments);
  }
}
