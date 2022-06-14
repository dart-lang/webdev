// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:async/async.dart';
import 'package:logging/logging.dart';

// ignore: import_of_legacy_library_into_null_safe
import '../daemon/app_domain.dart';
import '../daemon/daemon.dart';
import '../daemon/daemon_domain.dart';
import '../logging.dart';
import '../serve/dev_workflow.dart';
import '../serve/utils.dart';
// ignore: import_of_legacy_library_into_null_safe
import 'configuration.dart';
import 'shared.dart';

Stream<Map<String, dynamic>> get _stdinCommandStream => stdin
        .transform<String>(utf8.decoder)
        .transform<String>(const LineSplitter())
        .where((String line) => line.startsWith('[{') && line.endsWith('}]'))
        .map<Map<String, dynamic>>((String line) {
      line = line.substring(1, line.length - 1);
      return json.decode(line) as Map<String, dynamic>;
    });

void _stdoutCommandResponse(Map<String, dynamic> command) {
  stdout.writeln('[${json.encode(command)}]');
}

/// A mode for running WebDev from command-line tools.
///
/// Communication happens over STDIO using JSON-RPC.
///
/// This supports a subset of:
/// https://github.com/flutter/flutter/blob/master/packages/flutter_tools/doc/daemon.md
class DaemonCommand extends Command<int> {
  @override
  final name = 'daemon';

  @override
  final hidden = true;

  @override
  String get description =>
      'A mode for running WebDev from command-line tools.';

  @override
  final argParser = ArgParser()
    ..addMultiOption('launch-app', help: 'The html file to launch in chrome.');

  DaemonCommand() {
    addSharedArgs(argParser, releaseDefault: false);
  }

  @override
  Future<int> run() async {
    var configuration = Configuration.fromArgs(argResults,
        defaultConfiguration: Configuration(
            launchInChrome: true, debug: true, autoRun: false, release: false));
    configureLogWriter(configuration.verbose);
    // Validate the pubspec first to ensure we are in a Dart project.
    var pubspecLock = await readPubspecLock(configuration);

    Daemon? daemon;
    DevWorkflow? workflow;
    var cancelCount = 0;
    var cancelSub = StreamGroup.merge([
      ProcessSignal.sigint.watch(),
      // SIGTERM is not supported on Windows.
      Platform.isWindows ? const Stream.empty() : ProcessSignal.sigterm.watch()
    ]).listen((signal) async {
      cancelCount++;
      daemon?.shutdown();
      if (cancelCount > 1) exit(1);
    });
    try {
      daemon = Daemon(_stdinCommandStream, _stdoutCommandResponse);
      var daemonDomain = DaemonDomain(daemon);
      configureLogWriter(configuration.verbose, customLogWriter:
          (level, message, {loggerName, error, stackTrace, verbose}) {
        if (configuration.verbose || level >= Level.INFO) {
          daemonDomain.sendEvent('daemon.log', {
            'log': formatLog(
              level,
              message,
              loggerName: loggerName,
              error: error,
              stackTrace: stackTrace,
            )
          });
        }
      });
      daemon.registerDomain(daemonDomain);
      var buildOptions = buildRunnerArgs(pubspecLock, configuration);
      var directoryArgs =
          argResults!.rest.where((arg) => !arg.startsWith('-')).toList();
      var targetPorts =
          parseDirectoryArgs(directoryArgs, basePort: await findUnusedPort());
      validateLaunchApps(configuration.launchApps, targetPorts.keys);

      workflow =
          await DevWorkflow.start(configuration, buildOptions, targetPorts);
      daemon.registerDomain(AppDomain(daemon, workflow.serverManager));
      await daemon.onExit;
      exitCode = 0;
      return 0;
    } catch (e) {
      daemon?.shutdown();
      exitCode = 1;
      rethrow;
    } finally {
      await workflow?.shutDown();
      // Only cancel this subscription after all shutdown work has completed.
      // https://github.com/dart-lang/sdk/issues/23074.
      await cancelSub.cancel();
      // For some reason Windows remains open due to what appears to be an
      // undrained `stdin`. Feel free to waste some time trying to remove this.
      if (Platform.isWindows) exit(exitCode);
    }
  }
}
