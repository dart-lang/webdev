// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:logging/logging.dart';

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
    if (argResults.rest.isNotEmpty) {
      throw UsageException(
          'Arguments were provided that are not supported: '
          '"${argResults.rest.join(' ')}".',
          argParser.usage);
    }

    var configuration = Configuration.fromArgs(argResults);
    setVerbosity(configuration.verbose);
    var pubspecLock = await readPubspecLock(configuration);
    final arguments =
        buildRunnerArgs(pubspecLock, configuration, includeOutput: false);

    try {
      logHandler(Level.INFO, 'Connecting to the build daemon...');
      var client = await connectClient(
        Directory.current.path,
        arguments,
        (serverLog) {
          var recordLevel = levelForLog(serverLog) ?? Level.INFO;
          logHandler(recordLevel, trimLevel(recordLevel, serverLog.log));
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
      client.startBuild();
      var exitCode = 0;
      var gotBuildStart = false;
      await for (final result in client.buildResults) {
        var targetResult = result.results.firstWhere(
            (buildResult) => buildResult.target == configuration.outputInput,
            orElse: () => null);
        if (targetResult == null) continue;
        if (!gotBuildStart) {
          if (targetResult.status == BuildStatus.started) {
            gotBuildStart = true;
          }
        } else {
          if (targetResult.status == BuildStatus.started) {
            // Shouldn't happen, but just in case.
            continue;
          }

          if (targetResult.status == BuildStatus.failed) {
            exitCode = 1;
          }
          if (targetResult.error?.isNotEmpty == true) {
            logHandler(Level.SEVERE, targetResult.error);
          }
          break;
        }
      }
      await client.close();
      return exitCode;
    } on OptionsSkew catch (_) {
      logHandler(
          Level.SEVERE,
          'Incompatible options with current running build daemon.\n\n'
          'Please stop other WebDev instances running in this directory '
          'before starting a new instance with these options.\n\n');
      return 1;
    }
  }
}
