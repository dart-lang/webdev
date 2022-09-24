// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';
import 'dart:io' show Directory;

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:logging/logging.dart' as logging;

import '../daemon_client.dart';
import '../logging.dart';
import 'configuration.dart';
import 'shared.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends Command<int> {
  @override
  final argParser = ArgParser(usageLineLength: lineLength);

  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  BuildCommand() {
    addSharedArgs(argParser, outputDefault: 'web:build');
  }

  @override
  Future<int> run() async {
    var unsupported =
        argResults.rest.where((arg) => !arg.startsWith('-')).toList();
    if (unsupported.isNotEmpty) {
      throw UsageException(
          'Arguments were provided that are not supported: '
          '"${unsupported.join(' ')}".',
          argParser.usage);
    }
    var extraArgs =
        argResults.rest.where((arg) => arg.startsWith('-')).toList();

    var configuration = Configuration.fromArgs(argResults);
    configureLogWriter(configuration.verbose);
    var pubspecLock = await readPubspecLock(configuration);
    final arguments = buildRunnerArgs(pubspecLock, configuration)
      ..addAll(extraArgs);

    try {
      logWriter(logging.Level.INFO, 'Connecting to the build daemon...');
      var client = await connectClient(
        Directory.current.path,
        arguments,
        (serverLog) {
          logWriter(toLoggingLevel(serverLog.level), serverLog.message,
              error: serverLog.error,
              loggerName: serverLog.loggerName,
              stackTrace: serverLog.stackTrace);
        },
      );
      OutputLocation outputLocation;
      if (configuration.outputPath != null) {
        outputLocation = OutputLocation((b) => b
          ..output = configuration.outputPath
          ..useSymlinks = false
          ..hoist = configuration.outputInput.isNotEmpty);
      }
      client.registerBuildTarget(DefaultBuildTarget((b) => b
        ..target = configuration.outputInput
        ..outputLocation = outputLocation?.toBuilder()));

      // If we're supposed to do a full build, add an empty target so that all
      // assets are built.
      if (configuration.fullBuild) {
        client.registerBuildTarget(DefaultBuildTarget((b) => b..target = ''));
      }

      client.startBuild();
      var exitCode = 0;
      var gotBuildStart = false;
      await for (final result in client.buildResults) {
        var targetResult = result.results.firstWhere(
            (buildResult) => buildResult.target == configuration.outputInput,
            orElse: () => null);
        if (targetResult == null) continue;
        // We ignore any builds that happen before we get a `started` event,
        // because those could be stale (from some other client).
        gotBuildStart =
            gotBuildStart || targetResult.status == BuildStatus.started;
        if (!gotBuildStart) continue;

        // Shouldn't happen, but being a bit defensive here.
        if (targetResult.status == BuildStatus.started) continue;

        if (targetResult.status == BuildStatus.failed) {
          exitCode = 1;
        }

        if (targetResult.error?.isNotEmpty == true) {
          logWriter(logging.Level.SEVERE, targetResult.error);
        }
        break;
      }
      await client.close();
      return exitCode;
    } on OptionsSkew catch (_) {
      logWriter(
          logging.Level.SEVERE,
          'Incompatible options with current running build daemon.\n\n'
          'Please stop other WebDev instances running in this directory '
          'before starting a new instance with these options.\n\n');
      return 1;
    }
  }
}
