// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;

// ignore: import_of_legacy_library_into_null_safe
import '../command/configuration.dart';
import '../daemon_client.dart';
import '../logging.dart';
import 'chrome.dart';
import 'server_manager.dart';
// ignore: import_of_legacy_library_into_null_safe
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

String _uriForLaunchApp(String launchApp, ServerManager serverManager) {
  var parts = p.url.split(launchApp);
  var dir = parts.first;
  var server =
      serverManager.servers.firstWhere((server) => server.target == dir);
  return Uri(
          scheme: 'http',
          host: server.host,
          port: server.port,
          pathSegments: parts.skip(1))
      .toString();
}

Future<Chrome?> _startChrome(
  Configuration configuration,
  ServerManager serverManager,
  BuildDaemonClient client,
) async {
  var uris = [
    if (configuration.launchApps.isEmpty)
      for (var s in serverManager.servers)
        Uri(scheme: 'http', host: s.host, port: s.port).toString()
    else
      for (var app in configuration.launchApps)
        _uriForLaunchApp(app, serverManager)
  ];
  try {
    if (configuration.launchInChrome) {
      var userDataDir = configuration.userDataDir == autoOption
          ? autoDetectChromeUserDataDirectory()
          : configuration.userDataDir;
      return await Chrome.start(uris,
          port: configuration.chromeDebugPort, userDataDir: userDataDir);
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
) async {
  var assetPort = daemonPort(workingDirectory);
  var serverOptions = <ServerOptions>{};
  for (var target in targetPorts.keys) {
    serverOptions.add(ServerOptions(
      configuration,
      targetPorts[target]!,
      target,
      assetPort,
    ));
  }
  logWriter(logging.Level.INFO, 'Starting resource servers...');
  var serverManager =
      await ServerManager.start(serverOptions, client.buildResults);

  for (var server in serverManager.servers) {
    logWriter(
        logging.Level.INFO,
        'Serving `${server.target}` on '
        '${Uri(scheme: server.protocol, host: server.host, port: server.port)}\n');
  }

  return serverManager;
}

void _registerBuildTargets(
  BuildDaemonClient client,
  Configuration configuration,
  Map<String, int> targetPorts,
) {
  // Register a target for each serve target.
  for (var target in targetPorts.keys) {
    OutputLocation? outputLocation;
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
  if (configuration.outputInput == '' && configuration.outputPath != null) {
    var outputLocation = OutputLocation((b) => b
      ..output = configuration.outputPath
      ..useSymlinks = true
      ..hoist = false);
    client.registerBuildTarget(DefaultBuildTarget((b) => b
      ..target = ''
      ..outputLocation = outputLocation.toBuilder()));
  }
}

/// Controls the web development workflow.
///
/// Connects to the Build Daemon, creates servers, launches Chrome and wires up
/// the DevTools.
class DevWorkflow {
  final _doneCompleter = Completer();
  final BuildDaemonClient _client;
  final Chrome? _chrome;

  final ServerManager serverManager;
  late StreamSubscription _resultsSub;

  final _wrapWidth = stdout.hasTerminal ? stdout.terminalColumns - 8 : 72;

  DevWorkflow._(
    this._client,
    this._chrome,
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
    var serverManager = await _startServerManager(
        configuration, targetPorts, workingDirectory, client);
    var chrome = await _startChrome(configuration, serverManager, client);
    return DevWorkflow._(client, chrome, serverManager);
  }

  Future<void> shutDown() async {
    await _resultsSub.cancel();
    await _chrome?.close();
    await _client.close();
    await serverManager.stop();
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}
