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
}
