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

/// Controls the serve behavior of WebDev.
///
/// Connects to the Build Daemon, creates servers, launches Chrome and wires up
/// the DevTools.
class ServeController {
  final _doneCompleter = Completer();
  final BuildDaemonClient client;
  final ServerManager serverManager;
  final DevTools devTools;
  final Chrome chrome;

  ServeController._(
    this.client,
    this.serverManager,
    this.chrome,
    this.devTools,
  );

  Future<void> get done => _doneCompleter.future;

  static Future<ServeController> start(
    Configuration configuration,
    List<String> buildOptions,
    Map<String, int> targetPorts,
    void Function(Level level, String message) logHandler,
  ) async {
    var workingDirectory = Directory.current.path;

    logHandler(Level.INFO, 'Connecting to the build daemon...');

    BuildDaemonClient client;
    try {
      client = await connectClient(
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

    logHandler(Level.INFO, 'Registering build targets...');
    for (var target in targetPorts.keys) {
      client.registerBuildTarget(DefaultBuildTarget((b) => b.target = target));
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

    logHandler(Level.INFO, 'Starting resource servers...');
    var serverManager = await ServerManager.start(
        serverOptions, client.buildResults, devToolsCompleter.future);

    var uris = serverManager.servers
        .map((s) => 'http://${s.host}:${s.port}/')
        .toList();

    for (var server in serverManager.servers) {
      logHandler(
          Level.INFO,
          'Serving `${server.target}` on '
          'http://${server.host}:${server.port}\n');
    }

    Chrome chrome;
    DevTools devTools;
    try {
      if (configuration.launchInChrome) {
        chrome = await Chrome.start(uris, port: configuration.chromeDebugPort);
      } else if (configuration.chromeDebugPort != 0) {
        chrome = await Chrome.fromExisting(configuration.chromeDebugPort);
      }

      if (configuration.debug) {
        devTools = await DevTools.start(configuration.hostname, chrome);
        devToolsCompleter.complete(devTools);
        logHandler(Level.INFO,
            'Serving DevTools at http://${devTools.hostname}:${devTools.port}');
      } else {
        devToolsCompleter.complete(null);
      }
    } on ChromeError {
      await serverManager.stop();
      await client.close();
      rethrow;
    }

    logHandler(Level.INFO, 'Starting initial build...');
    client.startBuild();
    return ServeController._(client, serverManager, chrome, devTools);
  }

  Future<void> shutDown() async {
    await chrome?.close();
    await client?.close();
    await serverManager?.stop();
    await devTools?.close();
    if (!_doneCompleter.isCompleted) _doneCompleter.complete();
  }
}
