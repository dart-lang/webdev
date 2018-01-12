import 'dart:async';
import 'dart:isolate';

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
    var exitPort = new ReceivePort();
    await Isolate.spawnUri(await buildRunnerScript, arguments, null,
        onExit: exitPort.sendPort, automaticPackageResolution: true);
    await exitPort.first;
  }
}
