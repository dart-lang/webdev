// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:path/path.dart' as p;

/// Connects to the `build_runner` daemon.
Future<BuildDaemonClient> connectClient(String workingDirectory,
        List<String> options, Function(ServerLog) logHandler) =>
    BuildDaemonClient.connect(
        workingDirectory,
        // On Windows we need to call the snapshot directly otherwise
        // the process will start in a disjoint cmd without access to
        // STDIO. We also want to ensure the version of pub is consistent with
        // the SDK that was used to launch webdev.
        [dartPath, pubSnapshot]
          ..addAll(['run', 'build_runner', 'daemon'])
          ..addAll(options),
        logHandler: logHandler);

/// The path to the root directory of the SDK.
final String _sdkDir = (() {
  // The Dart executable is in "/path/to/sdk/bin/dart", so two levels up is
  // "/path/to/sdk".
  var aboveExecutable = p.dirname(p.dirname(Platform.resolvedExecutable));
  assert(FileSystemEntity.isFileSync(p.join(aboveExecutable, 'version')));
  return aboveExecutable;
})();

final String dartSdkPath = _sdkDir;
final String dartPath = p.join(_sdkDir, 'bin', 'dart');
final String pubSnapshot =
    p.join(_sdkDir, 'bin', 'snapshots', 'pub.dart.snapshot');
final String pubPath =
    p.join(_sdkDir, 'bin', Platform.isWindows ? 'pub.bat' : 'pub');

/// Returns the port of the daemon asset server.
int daemonPort(String workingDirectory) {
  var portFile = File(_assetServerPortFilePath(workingDirectory));
  if (!portFile.existsSync()) {
    throw Exception('Unable to read daemon asset port file.');
  }
  return int.parse(portFile.readAsStringSync());
}

String _assetServerPortFilePath(String workingDirectory) =>
    '${daemonWorkspace(workingDirectory)}/.asset_server_port';

void printError(String message, {StackTrace stackTrace}) {
  if (stackTrace != null) {
    print('$message: $stackTrace');
  }
  print(message);
}
