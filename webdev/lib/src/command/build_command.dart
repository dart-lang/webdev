import 'dart:async';
import 'package:io/io.dart';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends Command {
  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  // TODO(nshahan) Remove once we are not just passing all arguments through.
  final _anyArgs = new ArgParser(allowTrailingOptions: false);
  @override
  ArgParser get argParser => _anyArgs;

  @override
  Future run() async {
    // TODO(nshahan) Is there a better way to pipe standard out/in?
    // Would like to have consistent colors and spacing with build_runner.
    final manager = new ProcessManager();
    final executable = 'pub';
    final arguments = ['run', 'build_runner', 'build'];
    arguments.addAll(argResults.rest);
    var spawn = await manager.spawn(executable, arguments);

    await spawn.exitCode;
    await sharedStdIn.terminate();
  }
}
