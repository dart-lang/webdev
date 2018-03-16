import 'dart:async';

import 'build_runner_command_base.dart';

/// Command to execute pub run build_runner serve.
class ServeCommand extends BuildRunnerCommandBase {
  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that re-builds on changes.';

  ServeCommand() {
    // TODO(nshahan) Expose more args passed to build_runner serve.
    // build_runner might expose args for use in wrapping scripts like this one.
    argParser
      ..addOption('hostname',
          help: 'Specify the hostname to serve on', defaultsTo: 'localhost')
      ..addFlag('log-requests',
          defaultsTo: false,
          negatable: false,
          help: 'Enables logging for each request to the server.');
  }

  @override
  Future run() => runCore('serve');
}
