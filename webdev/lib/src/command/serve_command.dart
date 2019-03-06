// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_target.dart';

import '../serve/chrome.dart';
import '../serve/daemon_client.dart';
import '../serve/debugger/devtools.dart';
import '../serve/server_manager.dart';
import '../serve/utils.dart';
import '../serve/webdev_server.dart';
import 'configuration.dart';
import 'shared.dart';

final _defaultWebDirs = const ['web', 'test', 'example', 'benchmark'];

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
  ServerManager _serverManager;
  Chrome _chrome;
  BuildDaemonClient _client;

  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that re-builds on changes.';

  ServeCommand() {
    addSharedArgs(argParser, releaseDefault: false);
    argParser
      ..addOption(chromeDebugPortFlag,
          help: 'Specify which port the Chrome debugger is listenting on. '
              'If used with $launchInChromeFlag Chrome will be started with the'
              ' debugger listening on this port.')
      ..addFlag(debuggerFlag,
          help: 'Enable the launching of DevTools (Alt + D). '
              'Must use with either --$launchInChromeFlag or '
              '--$chromeDebugPortFlag.')
      ..addOption(hostnameFlag,
          help: 'Specify the hostname to serve on.', defaultsTo: 'localhost')
      ..addFlag(hotRestartFlag,
          negatable: false,
          help: 'Automatically reloads changed modules after each build '
              'and restarts your application.\n'
              "Can't be used with $liveReloadFlag.")
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
              "Can't be used with $hotRestartFlag.")
      ..addFlag(logRequestsFlag,
          negatable: false,
          help: 'Enables logging for each request to the server.');
  }

  @override
  String get invocation => '${super.invocation} [<directory>[:<port>]]...';

  @override
  Future<int> run() async {
    Configuration configuration;
    try {
      configuration = Configuration.fromArgs(argResults);
    } on InvalidConfiguration catch (e) {
      print('Invalid configuration: ${e.details}\n\n');
      printUsage();
      return -1;
    }

    var workingDirectory = Directory.current.path;

    var directoryArgs = argResults.rest
        .where((arg) => arg.contains(':') || !arg.startsWith('--'))
        .toList();

    var pubspecLock = await readPubspecLock(configuration);

    // Forward remaining arguments as Build Options to the Daemon.
    // This isn't documented. Should it be advertised?
    var buildOptions = buildRunnerArgs(pubspecLock, configuration)
      ..addAll(argResults.rest
          .where((arg) => !arg.contains(':') || arg.startsWith('--'))
          .toList());

    print('Connecting to the build daemon...');
    try {
      _client = await connectClient(
        workingDirectory,
        buildOptions,
        (serverLog) => writeServerLog(serverLog, configuration.verbose),
      );
    } on OptionsSkew {
      print('\nIncompatible options with current running build daemon.\n\n'
          'Please stop other WebDev instances running in this directory '
          'before starting a new instance with these options.');
      // TODO(grouma) - Give an option to kill the running daemon.
      return -1;
    }

    print('Registering build targets...');
    var targetPorts = _parseDirectoryArgs(directoryArgs);
    for (var target in targetPorts.keys) {
      _client.registerBuildTarget(DefaultBuildTarget((b) => b.target = target));
    }

    var assetPort = daemonPort(workingDirectory);
    var serverOptions = Set<ServerOptions>();
    for (var target in targetPorts.keys) {
      serverOptions.add(ServerOptions(
        configuration,
        targetPorts[target],
        target,
        assetPort,
      ));
    }

    var devToolsCompleter = Completer<DevTools>();

    _serverManager = ServerManager(
        serverOptions, _client.buildResults, devToolsCompleter.future);

    print('Starting resource servers...');
    await _serverManager.start();

    try {
      if (configuration.launchInChrome) {
        _chrome = await Chrome.start(_serverManager.uris,
            port: configuration.chromeDebugPort);
      } else if (configuration.chromeDebugPort != 0) {
        _chrome = await Chrome.fromExisting(configuration.chromeDebugPort);
      }

      if (configuration.debugger) {
        var devTools = await DevTools.start(configuration.hostname, _chrome);
        devToolsCompleter.complete(devTools);
      } else {
        devToolsCompleter.complete(null);
      }

      print('Starting initial build...');
      _client.startBuild();
      await _client.finished;
    } on ChromeError catch (e) {
      print(e.details);
    } finally {
      await shutDown();
    }

    return 0;
  }

  Future<void> shutDown() async {
    await _client?.close();
    await _serverManager?.stop();
    await _chrome?.close();
  }
}
