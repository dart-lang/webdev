// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:logging/logging.dart' as logging;
import 'package:meta/meta.dart';

import 'logging.dart';
import 'util.dart';

/// Exception thrown when connecting to or starting the build daemon fails.
class DaemonException implements Exception {
  final String message;

  DaemonException(this.message);

  @override
  String toString() => message;
}

const _optionsSkewMessage =
    'Incompatible options with current running build daemon.\n\n'
    'Please stop other WebDev instances running in this directory '
    'before starting a new instance with these options.';

const versionSkewMessage =
    'Incompatible build_daemon version detected.\n\n'
    'Try upgrading `build_daemon` in your project:\n\n'
    '  dart pub upgrade build_daemon\n\n'
    'If the issue persists, another dependency might be constraining '
    '`build_daemon` to an older version. Try running:\n\n'
    '  dart pub upgrade\n\n';

String _missingPortFileMessage(MissingPortFile error) =>
    '''
Failed to connect to the build daemon: $error

This usually happens when a previous `build_runner daemon` process exited
unexpectedly or is still shutting down, or when the project uses an older
`build_daemon` version than `webdev`.

Try:
  - Terminating any lingering `build_runner daemon` processes, removing
    `.dart_tool/build_daemon`, and retrying
  - Running `dart pub upgrade build_daemon` in your project
  - Re-activating `webdev` (`dart pub global activate webdev`)''';

/// Signature for connecting to a [BuildDaemonClient].
typedef ConnectClient = Future<BuildDaemonClient> Function(
  String workingDirectory,
  List<String> options,
  Function(ServerLog) logHandler,
);

/// Connects to the `build_runner` daemon.
Future<BuildDaemonClient> connectClient(
  String workingDirectory,
  List<String> options,
  Function(ServerLog) logHandler,
) => BuildDaemonClient.connect(workingDirectory, [
  dartPath,
  'run',
  'build_runner',
  'daemon',
  ...options,
], logHandler: logHandler);

/// Connects to the `build_runner` daemon and converts known connection failures
/// into [DaemonException].
Future<BuildDaemonClient> startBuildDaemon(
  String workingDirectory,
  List<String> buildOptions, {
  @visibleForTesting ConnectClient connect = connectClient,
}) async {
  try {
    logWriter(logging.Level.INFO, 'Connecting to the build daemon...');
    return await connect(workingDirectory, buildOptions, (serverLog) {
      logWriter(
        toLoggingLevel(serverLog.level),
        serverLog.message,
        loggerName: serverLog.loggerName,
        error: serverLog.error,
        stackTrace: serverLog.stackTrace,
      );
    });
  } on OptionsSkew {
    // TODO(grouma) - Give an option to kill the running daemon.
    throw DaemonException(_optionsSkewMessage);
  } on VersionSkew {
    throw DaemonException(versionSkewMessage);
  } on MissingPortFile catch (e) {
    throw DaemonException(_missingPortFileMessage(e));
  }
}

/// Returns the port of the daemon asset server.
int daemonPort(String workingDirectory) {
  final portFile = File(_assetServerPortFilePath(workingDirectory));
  if (!portFile.existsSync()) {
    throw Exception('Unable to read daemon asset port file.');
  }
  return int.parse(portFile.readAsStringSync());
}

String _assetServerPortFilePath(String workingDirectory) =>
    '${daemonWorkspace(workingDirectory)}/.asset_server_port';
