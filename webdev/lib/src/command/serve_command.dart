// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_target.dart';

import '../serve/daemon_client.dart';
import '../serve/server_manager.dart';
import '../serve/webdev_server.dart';
import 'command_base.dart';

const _hostnameFlag = 'hostname';
const _hotRestartFlag = 'hot-restart';
const _liveReloadFlag = 'live-reload';
const _logRequestsFlag = 'log-requests';
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
class ServeCommand extends CommandBase {
  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that re-builds on changes.';

  ServeCommand() : super(releaseDefault: false, outputDefault: outputNone) {
    argParser
      ..addOption(_hostnameFlag,
          help: 'Specify the hostname to serve on', defaultsTo: 'localhost')
      ..addFlag(_logRequestsFlag,
          defaultsTo: false,
          negatable: false,
          help: 'Enables logging for each request to the server.')
      ..addFlag(_liveReloadFlag,
          defaultsTo: false,
          negatable: false,
          help:
              'Automatically refreshes the page after each successful build.\n'
              "Can't be used with $_hotRestartFlag")
      ..addFlag(_hotRestartFlag,
          defaultsTo: false,
          negatable: false,
          help: 'Automatically reloads changed modules after each build '
              'and restarts your application.\n'
              "Can't be used with $_liveReloadFlag");
  }

  @override
  bool get hidden => true;

  @override
  String get invocation => '${super.invocation} [<directory>[:<port>]]...';

  @override
  Future<int> run() async {
    var workingDirectory = Directory.current.path;

    var hostname = argResults[_hostnameFlag] as String;
    var logRequests = argResults[_logRequestsFlag] as bool;
    var liveReload = argResults[_liveReloadFlag] as bool;
    var hotRestart = argResults[_hotRestartFlag] as bool;

    if (liveReload && hotRestart) {
      print("Can't use $liveReload and $hotRestart together\n\n");
      printUsage();
      return -1;
    }

    var directoryArgs = argResults.rest
        .where((arg) => arg.contains(':') || !arg.startsWith('--'))
        .toList();

    var pubspecLock = await readPubspecLock();

    // Forward remaining arguments as Build Options to the Daemon.
    // This isn't documented. Should it be advertised?
    var buildOptions = getArgs(pubspecLock)
      ..addAll(argResults.rest
          .where((arg) => !arg.contains(':') || arg.startsWith('--'))
          .toList());

    print('Connecting to the build daemon...');
    BuildDaemonClient client;
    try {
      client = await connectClient(workingDirectory, buildOptions);
    } on OptionsSkew {
      print('\nIncompatible options with current running build daemon.\n\n'
          'Please stop other WebDev instances running in this directory '
          'before starting a new instance with these options.');
      // TODO(grouma) - Give an option to kill the running daemon.
      return -1;
    }
    client.serverLogs.listen((serverLog) => print(serverLog.log));

    print('Registering build targets...');
    var targetPorts = _parseDirectoryArgs(directoryArgs);
    for (var target in targetPorts.keys) {
      client.registerBuildTarget(DefaultBuildTarget((b) => b.target = target));
    }

    var assetPort = daemonPort(workingDirectory);
    var serverOptions = Set<ServerOptions>();
    for (var target in targetPorts.keys) {
      serverOptions.add(ServerOptions(
        hostname,
        targetPorts[target],
        target,
        assetPort,
        liveReload,
        hotRestart,
        logRequests,
      ));
    }

    var manager = ServerManager(serverOptions, client.buildResults);

    print('Starting resource servers...');
    await manager.start();

    print('Starting initial build...');
    client.startBuild();

    await client.finished;
    await manager.stop();
    return 0;
  }
}
