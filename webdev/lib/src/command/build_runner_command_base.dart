import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:args/command_runner.dart';
import 'package:build_runner/src/logging/logging.dart';
import 'package:logging/logging.dart';

var _logger = new Logger('webdev');

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

  /// Runs `pub run build_runner` with [arguments] as an isolate.
  ///
  /// Attempts to run `pub get` and `pub upgrade` if needed and will retry
  /// running build_runner after.
  Future runBuildRunner(List<String> arguments) async {
    var exitPort = new ReceivePort();
    try {
      await Isolate.spawnUri(await _buildRunnerScript, arguments, null,
          onExit: exitPort.sendPort, automaticPackageResolution: true);
      await exitPort.first;
    } on _PubDependenciesError catch (_) {
      exitPort.close();
    }
  }

  Future<Uri> get _buildRunnerScript async {
    return await logTimedAsync(
        _logger, 'Generating build script', _runBuildRunnerGenerate);
  }

  /// Generates a build script and returns it's location.
  ///
  /// Will attempt to run `pub get` or `pub update` if needed.
  Future<Uri> _runBuildRunnerGenerate() async {
    // TODO(nshahan) build_runner will expose this as a function call that will
    // be imported to avoid running a binary in a transitive dependency with
    // pub run.
    final executable = 'pub';
    final arguments = ['run', 'build_runner', 'generate-build-script'];
    var result = await Process.run(executable, arguments);

    if (_needPubGet(result)) {
      _logger.warning('Generating build script failed.');
      result = await logTimedAsync(_logger, 'Getting dependencies', _runPubGet);

      // Try running build_runner again.
      result = await Process.run(executable, arguments);

      if (_needPubGet(result)) {
        _logger.warning('Getting dependencies failed.');
        result = await logTimedAsync(
            _logger, 'Upgrading dependencies', _runPubUpgrade);

        if (result.exitCode != 0) {
          _logger.severe(
              'Could not retrieve dependencies. webdev must be able to run `pub'
              ' get`.'
              '\nPlease fix the dependencies and retry.'
              '\n\n${result.stderr}');
          throw new _PubDependenciesError();
        }

        // Try running build_runner one last time.
        result = await Process.run(executable, arguments);
      }
    }

    return new Uri.file(result.stdout.toString().trim());
  }

  /// Checks [result] for errors to see if a `pub get` is needed.
  bool _needPubGet(ProcessResult result) =>
      result.exitCode != 0 &&
      result.stderr.toString().contains('please run "pub get"');

  /// Runs `pub get` as a Process.
  Future<ProcessResult> _runPubGet() async {
    return await Process.run('pub', ['get', '--no-precompile']);
  }

  /// Runs `pub upgrade` as a Process.
  Future<ProcessResult> _runPubUpgrade() async {
    return await Process.run('pub', ['upgrade', '--no-precompile']);
  }
}

/// Private error class used to report back an error when attempting to run
/// `pub get` and `pub upgrade`.
class _PubDependenciesError extends Error {}
