// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:dwds/src/devtools.dart'; // ignore: implementation_imports
import 'package:logging/logging.dart' as logging;

import '../command/configuration.dart';
import '../daemon_client.dart';
import '../logging.dart';
import 'chrome.dart';
import 'server_manager.dart';
import 'webdev_server.dart';

Future<BuildDaemonClient> _startBuildDaemon(
    String workingDirectory, List<String> buildOptions) async {
  try {
    logWriter(logging.Level.INFO, 'Connecting to the build daemon...');
    return await connectClient(
      workingDirectory,
      buildOptions,
      (serverLog) {
        logWriter(toLoggingLevel(serverLog.level), serverLog.message,
            loggerName: serverLog.loggerName,
            error: serverLog.error,
            stackTrace: serverLog.stackTrace);
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
  logWriter(logging.Level.INFO, 'Starting resource servers...');
  var serverManager =
      await ServerManager.start(serverOptions, client.buildResults, devTools);

  for (var server in serverManager.servers) {
    logWriter(
        logging.Level.INFO,
        'Serving `${server.target}` on '
        'http://${server.host}:${server.port}\n');
  }

  return serverManager;
}

Future<DevTools> _startDevTools(
  Configuration configuration,
) async {
  if (configuration.debug) {
    var devTools = await DevTools.start(configuration.hostname);
    logWriter(logging.Level.INFO,
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
  StreamSubscription _resultsSub;

  final _wrapWidth = stdout.hasTerminal ? stdout.terminalColumns - 8 : 72;

  DevWorkflow._(
    this._client,
    this._chrome,
    this._devTools,
    this.serverManager,
  ) {
    _resultsSub = _client.buildResults.listen((data) {
      if (data.results.any((result) =>
          result.status == BuildStatus.failed ||
          result.status == BuildStatus.succeeded)) {
        logWriter(logging.Level.INFO, '${'-' * _wrapWidth}\n');
      }
    });
    _client.shutdownNotifications.listen((data) {
      logWriter(logging.Level.WARNING, data.message);
      if (data.failureType == 75) {
        logWriter(logging.Level.WARNING, 'Please restart WebDev.\n');
      }
      shutDown();
    });
  }

  Future<void> get done => _doneCompleter.future;

  static Future<DevWorkflow> start(
    Configuration configuration,
    List<String> buildOptions,
    Map<String, int> targetPorts,
  ) async {
    var workingDirectory = Directory.current.path;
    var client = await _startBuildDaemon(workingDirectory, buildOptions);
    logWriter(logging.Level.INFO, 'Registering build targets...');
    _registerBuildTargets(client, configuration, targetPorts);
    logWriter(logging.Level.INFO, 'Starting initial build...');
    client.startBuild();
    var devTools = await _startDevTools(configuration);
    var serverManager = await _startServerManager(
        configuration, targetPorts, workingDirectory, client, devTools);
    var chrome = await _startChrome(configuration, serverManager, client);
    return DevWorkflow._(client, chrome, devTools, serverManager);
  }

  Future<void> shutDown() async {
    await _resultsSub?.cancel();
    await _chrome?.close();
    await _client?.close();
    await _devTools?.close();
    await serverManager?.stop();
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}
