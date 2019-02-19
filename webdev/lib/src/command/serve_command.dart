// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_target.dart';

import '../pubspec.dart';
import '../serve/daemon_client.dart';
import '../serve/server_manager.dart';
import '../serve/utils.dart';
import '../serve/webdev_server.dart';

const _hostnameFlag = 'hostname';
const _hotReloadFlag = 'hot-reload';
const _hotRestartFlag = 'hot-restart';
const _liveReloadFlag = 'live-reload';
const _logRequestsFlag = 'log-requests';
const _outputFlag = 'output';
const _releaseFlag = 'release';
const _requireBuildWebCompilers = 'build-web-compilers';
const _verboseFlag = 'verbose';
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
  @override
  final name = 'serve';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that re-builds on changes.';

  ServeCommand() {
    argParser
      ..addOption(_hostnameFlag,
          help: 'Specify the hostname to serve on', defaultsTo: 'localhost')
      ..addFlag(_hotRestartFlag,
          defaultsTo: false,
          negatable: false,
          help: 'Automatically reloads changed modules after each build '
              'and restarts your application.\n'
              "Can't be used with $_liveReloadFlag")
      ..addFlag(_hotReloadFlag, defaultsTo: false, negatable: false, hide: true)
      ..addFlag(_liveReloadFlag,
          defaultsTo: false,
          negatable: false,
          help:
              'Automatically refreshes the page after each successful build.\n'
              "Can't be used with $_hotRestartFlag")
      ..addFlag(_logRequestsFlag,
          defaultsTo: false,
          negatable: false,
          help: 'Enables logging for each request to the server.')
      ..addOption(
        _outputFlag,
        abbr: 'o',
        defaultsTo: 'NONE',
        help: 'A directory to write the result of a build to. Or a mapping '
            'from a top-level directory in the package to the directory to '
            'write a filtered build output to. For example "web:deploy".\n'
            'A value of "NONE" indicates that no "--output" value should be '
            'passed to `build_runner`.',
      )
      ..addFlag(_releaseFlag,
          abbr: 'r',
          defaultsTo: false,
          negatable: true,
          help: 'Build with release mode defaults for builders.')
      ..addFlag(_requireBuildWebCompilers,
          defaultsTo: true,
          negatable: true,
          help: 'If a dependency on `build_web_compilers` is required to run.')
      ..addFlag(_verboseFlag,
          abbr: 'v',
          defaultsTo: false,
          negatable: false,
          help: 'Enables verbose logging.');
  }

  @override
  String get invocation => '${super.invocation} [<directory>[:<port>]]...';

  List<String> buildRunnerArgs(PubspecLock pubspecLock) {
    var arguments = <String>[];
    if (argResults[_releaseFlag] as bool) {
      arguments.add('--$_releaseFlag');
    }

    var output = argResults[_outputFlag] as String;
    if (output != null && output != 'NONE') {
      arguments.addAll(['--$_outputFlag', output]);
    }

    if (argResults[_verboseFlag] as bool) {
      arguments.add('--$_verboseFlag');
    }
    return arguments;
  }

  Future<PubspecLock> readPubspecLock([String path]) async {
    var pubspecLock = await PubspecLock.read(path);
    await checkPubspecLock(pubspecLock,
        requireBuildWebCompilers:
            argResults[_requireBuildWebCompilers] as bool);
    return pubspecLock;
  }

  @override
  Future<int> run() async {
    var workingDirectory = Directory.current.path;

    var hostname = argResults[_hostnameFlag] as String;
    var logRequests = argResults[_logRequestsFlag] as bool;
    var liveReload = argResults[_liveReloadFlag] as bool;
    var hotRestart = argResults[_hotRestartFlag] as bool;
    var hotReload = argResults[_hotReloadFlag] as bool;
    var verbose = argResults[_verboseFlag] as bool;

    if (hotReload) {
      print('Hot reload is not ready yet, using --$_hotRestartFlag');
      hotRestart = true;
    }

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
    var buildOptions = buildRunnerArgs(pubspecLock)
      ..addAll(argResults.rest
          .where((arg) => !arg.contains(':') || arg.startsWith('--'))
          .toList());

    print('Connecting to the build daemon...');
    BuildDaemonClient client;
    try {
      client = await connectClient(
        workingDirectory,
        buildOptions,
        (serverLog) => writeServerLog(serverLog, verbose),
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
