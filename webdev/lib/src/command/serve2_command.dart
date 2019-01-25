// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:webdev/src/pubspec.dart';

import '../serve/daemon_client.dart';
import '../serve/server_manager.dart';
import 'command_base.dart';

Map<String, int> _parseDirectoryArgs(List<String> args) {
  var result = <String, int>{};
  for (var arg in args) {
    var splitOption = arg.split(':');
    assert(splitOption.length == 2);
    result[splitOption.first] = int.parse(splitOption.last);
  }
  return result;
}

/// Command to run a server for local web development.
///
/// This command will eventually replace the existing serve command.
class Serve2Command extends CommandBase {
  @override
  final name = 'serve2';

  @override
  final description = 'Run a local web development server and a file system'
      ' watcher that re-builds on changes.';

  Serve2Command() : super(releaseDefault: false, outputDefault: outputNone) {
    argParser
      ..addOption('hostname',
          help: 'Specify the hostname to serve on', defaultsTo: 'localhost')
      ..addFlag('log-requests',
          defaultsTo: false,
          negatable: false,
          help: 'Enables logging for each request to the server.')
      // For development purposes.
      ..addOption(
        'working-directory',
        hide: true,
        help: 'Set the working directory for this command.',
      );
  }

  @override
  bool get hidden => true;

  @override
  String get invocation => '${super.invocation} [<directory>[:<port>]]...';

  @override
  List<String> getArgs(PubspecLock pubspecLock) {
    var issues = pubspecLock.checkPackage(
        'build_runner', new VersionConstraint.parse('>=1.2.0 <2.0.0'));
    if (issues.isNotEmpty) throw new PackageException(issues);
    return super.getArgs(pubspecLock);
  }

  @override
  Future<int> run() async {
    var workingDirectory = argResults['working-directory'] as String;
    workingDirectory ??= Directory.current.path;

    var hostname = argResults['hostname'] as String;
    var logRequests = argResults['log-requests'] as bool;

    var directoryArgs =
        argResults.rest.where((arg) => arg.contains(':')).toList();
    if (directoryArgs.isEmpty) {
      print('No directories provided.\n\n');
      printUsage();
      return -1;
    }

    var pubspecLock = await readPubspecLock('$workingDirectory/pubspec.lock');
    // Forward remaining arguments as Build Options to the Daemon
    var buildOptions = getArgs(pubspecLock)
      ..addAll(argResults.rest.where((arg) => !arg.contains(':')).toList());

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

    var manager = ServerManager(
      getDaemonPort(workingDirectory),
      hostname,
      targetPorts,
      logRequests,
    );

    print('Starting resource servers...');
    await manager.start();

    print('Starting initial build...');
    client.startBuild();

    await client.finished;
    await manager.stop();
    return 0;
  }
}
