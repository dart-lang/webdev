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
    final result = await _runBuildRunnerGenerate();

    if (result.exitCode != 0) {
      print(result.exitCode);
      _logger.severe('Unable to run `pub get` and `pub run build_runner`.'
          '\nPlease fix the dependencies and retry.'
          '\n\n${result.stderr}');
      return;
    }

    var exitPort = new ReceivePort();
    var errorPort = new ReceivePort();
    var messagePort = new ReceivePort();
    var errorListener = errorPort.listen((e) {
      stderr.writeAll(e as List, '\n');
      if (exitCode == 0) exitCode = 1;
    });
    await Isolate.spawnUri(_scriptPath(result), arguments, messagePort.sendPort,
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
        automaticPackageResolution: true);
    try {
      exitCode = await messagePort.first as int;
    } on StateError catch (_) {
      if (exitCode == 0) exitCode = 1;
    }
    await exitPort.first;
    await errorListener.cancel();
  }

  /// Generates a build script and returns it's location.
  ///
  /// Will attempt to get dependencies if needed.
  Future<ProcessResult> _runBuildRunnerGenerate() async {
    var result = await logTimedAsync(
        _logger, 'Generating build script', _runGenerateBuildScript);

    if (result.exitCode != 0) {
      _logger.warning('Generating build script failed.');
      result = await logTimedAsync(_logger, 'Getting dependencies', _runPubGet);

      if (result.exitCode != 0) {
        _logger.warning('Getting dependencies failed.');
        result = await logTimedAsync(
            _logger, 'Upgrading dependencies', _runPubUpgrade);

        if (result.exitCode != 0) {
          _logger.severe('Upgrading dependencies failed');
          return result;
        }
      }

      // Try running build_runner again.
      result = await logTimedAsync(
          _logger, 'Generating build script', _runGenerateBuildScript);
    }

    return result;
  }

  /// Parses the generated script path from the the results of running
  /// `build_runner generate-build-script`.`
  Uri _scriptPath(ProcessResult result) =>
      new Uri.file(result.stdout.toString().trim());

  /// Runs `build_runner generate-build-script` as a Process.
  Future<ProcessResult> _runGenerateBuildScript() =>
      // TODO(nshahan) build_runner will expose this as a function call that
      // will be imported to avoid running a binary in a transitive dependency
      // with pub run.
      Process.run('pub', ['run', 'build_runner', 'generate-build-script']);

  /// Runs `pub get` as a Process.
  Future<ProcessResult> _runPubGet() =>
      Process.run('pub', ['get', '--no-precompile']);

  /// Runs `pub upgrade` as a Process.
  Future<ProcessResult> _runPubUpgrade() =>
      Process.run('pub', ['upgrade', '--no-precompile']);
}
