// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:logging/logging.dart';

import '../command/configuration.dart';
import '../serve/chrome.dart';
import '../serve/daemon_client.dart';
import '../serve/debugger/devtools.dart';
import '../serve/server_manager.dart';
import '../serve/utils.dart';
import '../serve/webdev_server.dart';

Future<BuildDaemonClient> _startBuildDaemon(
  String workingDirectory,
  List<String> buildOptions,
  void Function(Level level, String message) logHandler,
) async {
  logHandler(Level.INFO, 'Connecting to the build daemon...');
  try {
    return await connectClient(
      workingDirectory,
      buildOptions,
      (serverLog) {
        var recordLevel = levelForLog(serverLog) ?? Level.INFO;
        logHandler(recordLevel, trimLevel(recordLevel, serverLog.log));
      },
    );
  } on OptionsSkew {
    // TODO(grouma) - Give an option to kill the running daemon.
    throw StateError(
        'Incompatible options with current running build daemon.\n\n'
        'Please stop other WebDev instances running in this directory '
        'before starting a new instance with these options.');
  }
}

Future<Chrome> _startChrome(
  Configuration configuration,
  ServerManager serverManager,
  BuildDaemonClient client,
) async {
  var uris =
      serverManager.servers.map((s) => 'http://${s.host}:${s.port}/').toList();
  try {
    if (configuration.launchInChrome) {
      return await Chrome.start(uris, port: configuration.chromeDebugPort);
    } else if (configuration.chromeDebugPort != 0) {
      return await Chrome.fromExisting(configuration.chromeDebugPort);
    }
  } on ChromeError {
    await serverManager.stop();
    await client.close();
    rethrow;
  }
  return null;
}

Future<ServerManager> _startServerManager(
  Configuration configuration,
  Map<String, int> targetPorts,
  String workingDirectory,
  BuildDaemonClient client,
  DevTools devTools,
  void Function(Level level, String message) logHandler,
) async {
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
  logHandler(Level.INFO, 'Starting resource servers...');
  var serverManager =
      await ServerManager.start(serverOptions, client.buildResults, devTools);

  for (var server in serverManager.servers) {
    logHandler(
        Level.INFO,
        'Serving `${server.target}` on '
        'http://${server.host}:${server.port}\n');
  }

  return serverManager;
}

Future<DevTools> _startDevTools(
  Configuration configuration,
  void Function(Level level, String message) logHandler,
) async {
  if (configuration.debug) {
    var devTools = await DevTools.start(configuration.hostname);
    logHandler(Level.INFO,
        'Serving DevTools at http://${devTools.hostname}:${devTools.port}\n');
    return devTools;
  }
  return null;
}

void _registerBuildTargets(
  BuildDaemonClient client,
  Configuration configuration,
  Map<String, int> targetPorts,
) {
  // Register a target for each serve target.
  for (var target in targetPorts.keys) {
    OutputLocation outputLocation;
    if (configuration.outputPath != null &&
        (configuration.outputInput == null ||
            target == configuration.outputInput)) {
      outputLocation = OutputLocation((b) => b
        ..output = configuration.outputPath
        ..useSymlinks = true
        ..hoist = true);
    }
    client.registerBuildTarget(DefaultBuildTarget((b) => b
      ..target = target
      ..outputLocation = outputLocation?.toBuilder()));
  }
  // Empty string indicates we should build everything, register a corresponding
  // target.
  if (configuration.outputInput == '') {
    var outputLocation = OutputLocation((b) => b
      ..output = configuration.outputPath
      ..useSymlinks = true
      ..hoist = false);
    client.registerBuildTarget(DefaultBuildTarget((b) => b
      ..target = ''
      ..outputLocation = outputLocation?.toBuilder()));
  }
}

/// Controls the web development workflow.
///
/// Connects to the Build Daemon, creates servers, launches Chrome and wires up
/// the DevTools.
class DevWorkflow {
  final _doneCompleter = Completer();
  final BuildDaemonClient _client;
  final DevTools _devTools;
  final Chrome _chrome;

  final ServerManager serverManager;

  DevWorkflow._(
    this._client,
    this._chrome,
    this._devTools,
    this.serverManager,
  );

  Future<void> get done => _doneCompleter.future;

  static Future<DevWorkflow> start(
    Configuration configuration,
    List<String> buildOptions,
    Map<String, int> targetPorts,
    void Function(Level level, String message) logHandler,
  ) async {
    var workingDirectory = Directory.current.path;
    var client =
        await _startBuildDaemon(workingDirectory, buildOptions, logHandler);
    var devTools = await _startDevTools(configuration, logHandler);
    var serverManager = await _startServerManager(configuration, targetPorts,
        workingDirectory, client, devTools, logHandler);
    var chrome = await _startChrome(configuration, serverManager, client);
    logHandler(Level.INFO, 'Registering build targets...');
    _registerBuildTargets(client, configuration, targetPorts);
    logHandler(Level.INFO, 'Starting initial build...');
    client.startBuild();
    return DevWorkflow._(client, chrome, devTools, serverManager);
  }

  Future<void> shutDown() async {
    await _chrome?.close();
    await _client?.close();
    await _devTools?.close();
    await serverManager?.stop();
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}
