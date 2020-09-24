// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import '../logging.dart';
import '../serve/dev_workflow.dart';
import 'configuration.dart';
import 'shared.dart';

/// Command to run a server for local web development with the build daemon.
class ServeCommand extends Command<int> {
  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that rebuilds on changes.';

  @override
  final argParser = ArgParser(usageLineLength: lineLength)
    ..addOption(autoOption, help: '''
Automatically performs an action after each build:

restart: Reload modules and re-invoke main (loses current state)
refresh: Performs a full page refresh.
''', allowed: ['restart', 'refresh'])
    ..addFlag(debugFlag,
        help: 'Enable the launching of DevTools (Alt + D / Option + D). '
            'This also enables --$launchInChromeFlag.')
    ..addFlag(debugExtensionFlag,
        help: 'Enable the backend for the Dart Debug Extension.')
    ..addFlag(enableInjectedClientFlag,
        help: 'Whether or not to inject the client.js script in web apps. This '
            'is required for all debugging related features, but may interact '
            'poorly with proxy servers or other environments.',
        defaultsTo: true)
    ..addSeparator('Advanced:')
    ..addOption(chromeDebugPortFlag,
        help: 'Specify which port the Chrome debugger is listening on. '
            'If used with $launchInChromeFlag Chrome will be started with the'
            ' debugger listening on this port.')
    ..addFlag(disableDdsFlag,
        negatable: false,
        help: 'Disable the Dart Development Service (DDS). Disabling DDS may '
        'result in a degraded developer experience in some tools.')
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
        help: 'Automatically launches your application in Chrome with the '
            'debug port open. Use $chromeDebugPortFlag to specify a specific '
            'port to attach to an already running chrome instance instead.')
    ..addFlag(liveReloadFlag,
        negatable: false,
        help: 'Automatically refreshes the page after each successful build.\n'
            "Can't be used with $hotRestartFlag.",
        hide: true)
    ..addFlag(logRequestsFlag,
        negatable: false,
        help: 'Enables logging for each request to the server.')
    ..addOption(tlsCertChainFlag,
        help:
            'The file location to a TLS Certificate to create an HTTPs server.\n'
            'Must be used with $tlsCertKeyFlag.')
    ..addOption(tlsCertKeyFlag,
        help: 'The file location to a TLS Key to create an HTTPs server.\n'
            'Must be used with $tlsCertChainFlag.')
    ..addSeparator('Common:');

  ServeCommand() {
    addSharedArgs(argParser, releaseDefault: false);
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
    var buildOptions = buildRunnerArgs(pubspecLock, configuration)
      ..addAll(argResults.rest.where((arg) => arg.startsWith('-')).toList());
    var directoryArgs =
        argResults.rest.where((arg) => !arg.startsWith('-')).toList();
    var targetPorts = parseDirectoryArgs(directoryArgs);
    validateLaunchApps(configuration.launchApps, targetPorts.keys);

    var workflow =
        await DevWorkflow.start(configuration, buildOptions, targetPorts);
    await workflow.done;
    return 0;
  }
}
