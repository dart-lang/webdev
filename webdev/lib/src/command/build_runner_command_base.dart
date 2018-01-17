import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';

/// Extend to get a command with the arguments common to all build_runner
/// commands.
abstract class BuildRunnerCommandBase extends Command {
  BuildRunnerCommandBase() {
    // TODO(nshahan) Expose more common args passed to build_runner commands.
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

  Future<Uri> get buildRunnerScript async {
    // TODO(nshahan) build_runner will expose this as a function call that will
    // be imported to avoid running a binary in a transitive dependency with
    // pub run.
    final executable = 'pub';
    final arguments = ['run', 'build_runner', 'generate-build-script'];
    final results = await Process.run(executable, arguments);
    return new Uri.file(results.stdout.toString().trim());
  }
}
