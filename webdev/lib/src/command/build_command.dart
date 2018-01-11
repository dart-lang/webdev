import 'dart:async';
import 'package:io/io.dart';

import 'package:args/command_runner.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends Command {
  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  BuildCommand() {
    // TODO(nshahan) Expose more args passed to build_runner build.
    // build_runner might expose args for use in wrapping scripts like this one.
    argParser
      ..addOption('output',
          abbr: 'o', help: 'A directory to write the result of a build to.')
      ..addFlag('verbose',
          abbr: 'v',
          defaultsTo: false,
          negatable: false,
          help: 'Enables verbose logging.');
  }

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
