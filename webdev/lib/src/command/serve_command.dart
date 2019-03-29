// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../serve/dev_workflow.dart';
import '../serve/logging.dart';
import 'configuration.dart';
import 'shared.dart';

final _defaultWebDirs = const ['web'];

Map<String, int> _parseDirectoryArgs(List<String> args) {
  var result = <String, int>{};
  var basePort = 8080;
  if (args.isEmpty) {
    for (var dir in _defaultWebDirs) {
      if (Directory(dir).existsSync()) {
        result[dir] = basePort++;
      }
    }
  } else {
    for (var arg in args) {
      var splitOption = arg.split(':');
      if (splitOption.length == 2) {
        result[splitOption.first] = int.parse(splitOption.last);
      } else {
        result[arg] = basePort++;
      }
    }
  }
  return result;
}

/// Command to run a server for local web development with the build daemon.
class ServeCommand extends Command<int> {
  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that rebuilds on changes.';

  @override
  final argParser = ArgParser(usageLineLength: lineLength);

  ServeCommand() {
    addSharedArgs(argParser, releaseDefault: false);
    argParser
      ..addOption(autoOption, help: '''
Automatically performs an action after each build:

restart: Reload modules and re-invoke main (loses current state)
refresh: Performs a full page refresh.
''', allowed: ['restart', 'refresh'])
      ..addOption(chromeDebugPortFlag,
          help: 'Specify which port the Chrome debugger is listening on. '
              'If used with $launchInChromeFlag Chrome will be started with the'
              ' debugger listening on this port.')
      ..addFlag(debugFlag,
          help: 'Enable the launching of DevTools (Alt + D). '
              'Must use with either --$launchInChromeFlag or '
              '--$chromeDebugPortFlag.')
      ..addOption(hostnameFlag,
          help: 'Specify the hostname to serve on.', defaultsTo: 'localhost')
      ..addFlag(hotRestartFlag,
          negatable: false,
          help: 'Automatically reloads changed modules after each build '
              'and restarts your application.\n'
              "Can't be used with $liveReloadFlag.",
          hide: true)
      ..addFlag(hotReloadFlag, negatable: false, hide: true)
      ..addFlag(launchInChromeFlag,
          negatable: false,
          help: 'Automatically launches your application in Chrome with the '
              'debug port open. Use $chromeDebugPortFlag to specify a specific '
              'port.')
      ..addFlag(liveReloadFlag,
          negatable: false,
          help:
              'Automatically refreshes the page after each successful build.\n'
              "Can't be used with $hotRestartFlag.",
          hide: true)
      ..addFlag(logRequestsFlag,
          negatable: false,
          help: 'Enables logging for each request to the server.');
  }

  @override
  String get invocation => '${super.invocation} [<directory>[:<port>]]...';

  @override
  Future<int> run() async {
    Configuration configuration;
    configuration = Configuration.fromArgs(argResults);
    // Globally trigger verbose logs.
    setVerbosity(configuration.verbose);
    var pubspecLock = await readPubspecLock(configuration);
    // Forward remaining arguments as Build Options to the Daemon.
    // This isn't documented. Should it be advertised?
    var buildOptions =
        buildRunnerArgs(pubspecLock, configuration, includeOutput: false)
          ..addAll(argResults.rest
              .where((arg) => !arg.contains(':') || arg.startsWith('--'))
              .toList());
    var directoryArgs = argResults.rest
        .where((arg) => arg.contains(':') || !arg.startsWith('--'))
        .toList();
    var targetPorts = _parseDirectoryArgs(directoryArgs);
    var workflow =
        await DevWorkflow.start(configuration, buildOptions, targetPorts);
    await workflow.done;
    return 0;
  }
}
