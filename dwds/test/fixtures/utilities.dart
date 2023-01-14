// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:dwds/src/utilities/sdk_configuration.dart';
import 'package:path/path.dart' as p;

import 'sdk_asset_generator.dart';

const webdevDirName = 'webdev';
const dwdsDirName = 'dwds';
const fixturesDirName = 'fixtures';

/// The path to the webdev directory in the local machine, e.g.
/// '/workstation/webdev'.
String get webdevPath {
  final pathParts = p.split(p.current);
  // We expect all tests to be run from the webdev mono-repo:
  assert(pathParts.contains(webdevDirName));
  return p.joinAll(
    pathParts.sublist(0, pathParts.lastIndexOf(webdevDirName) + 1),
  );
}

/// The path to the DWDS directory in the local machine, e.g.
/// '/workstation/webdev/dwds'.
String get dwdsPath {
  return p.join(webdevPath, dwdsDirName);
}

/// The path to the fixtures directory in the local machine, e.g.
/// '/workstation/webdev/fixtures'.
String get fixturesPath {
  return p.join(webdevPath, fixturesDirName);
}

// Creates a path compatible for web.
String webCompatiblePath(List<String> pathParts) {
  // Note: Replacing "\" with "/" is necessary because `joinAll` uses "\" if
  // the platform is Windows. However, only "/" is expected by the browser.
  return p.joinAll([...pathParts]).replaceAll('\\', '/');
}

/// Expects one of [pathFromWebdev], [pathFromDwds] or [pathFromFixtures]  to be
/// provided. Returns the absolute path in the local machine to that path, e.g.
///   absolutePath(pathFromFixtures: '_test/example') ->
///   '/workstation/webdev/fixtures/_test/example'
String absolutePath({
  String? pathFromWebdev,
  String? pathFromDwds,
  String? pathFromFixtures,
}) {
  if (pathFromWebdev != null) {
    assert(pathFromDwds == null && pathFromFixtures == null);
    return p.normalize(p.join(webdevPath, pathFromWebdev));
  }
  if (pathFromDwds != null) {
    assert(pathFromFixtures == null);
    return p.normalize(p.join(dwdsPath, pathFromDwds));
  }
  if (pathFromFixtures != null) {
    assert(pathFromDwds == null && pathFromWebdev == null);
    return p.normalize(p.join(fixturesPath, pathFromFixtures));
  }
  throw Exception('Expected a path parameter.');
}

/// Connects to the `build_runner` daemon.
Future<BuildDaemonClient> connectClient(String workingDirectory,
        List<String> options, Function(ServerLog) logHandler) =>
    BuildDaemonClient.connect(workingDirectory,
        [dartPath, 'run', 'build_runner', 'daemon', ...options],
        logHandler: logHandler);

/// The path to the root directory of the SDK.
final String _sdkDir = (() {
  // The Dart executable is in "/path/to/sdk/bin/dart", so two levels up is
  // "/path/to/sdk".
  final aboveExecutable = p.dirname(p.dirname(Platform.resolvedExecutable));
  assert(FileSystemEntity.isFileSync(p.join(aboveExecutable, 'version')));
  return aboveExecutable;
})();

final String dartSdkPath = _sdkDir;
final String dartPath = p.join(_sdkDir, 'bin', 'dart');
final String devToolsPath = p.join(_sdkDir, 'bin', 'resources', 'devtools');

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

/// Retries a callback function with a delay until the result is non-null.
Future<T> retryFn<T>(
  T Function() callback, {
  int retryCount = 3,
  int delayInMs = 1000,
  String failureMessage = 'Function did not succeed after retries.',
}) async {
  if (retryCount == 0) {
    throw Exception(failureMessage);
  }

  await Future.delayed(Duration(milliseconds: delayInMs));
  try {
    final result = callback();
    if (result != null) return result;
  } catch (_) {
    // Ignore any exceptions.
  }

  return retryFn<T>(
    callback,
    retryCount: retryCount - 1,
    delayInMs: delayInMs,
    failureMessage: failureMessage,
  );
}

/// Retries an asynchronous callback function with a delay until the result is
/// non-null.
Future<T> retryFnAsync<T>(
  Future<T> Function() callback, {
  int retryCount = 3,
  int delayInMs = 1000,
  String failureMessage = 'Function did not succeed after retries.',
}) async {
  if (retryCount == 0) {
    throw Exception(failureMessage);
  }

  await Future.delayed(Duration(milliseconds: delayInMs));
  try {
    final result = await callback();
    if (result != null) return result;
  } catch (_) {
    // Ignore any exceptions.
  }

  return retryFnAsync<T>(
    callback,
    retryCount: retryCount - 1,
    delayInMs: delayInMs,
    failureMessage: failureMessage,
  );
}

/// Implementation for SDK configuration for tests that can generate
/// missing assets.
///
///  - Generate SDK js, source map, and full dill for weak and sound
///    modes (normally included in flutter SDK or produced by build).
///  - Need to generate SDK summary for weak null safety mode as it
///    is not provided by the SDK installation.
///
/// TODO(annagrin): update to only generating missing sound artifacts
/// for frontend server after we have no uses of weak null safety.
class TestSdkConfigurationProvider extends SdkConfigurationProvider {
  final bool _verboseCompiler;
  SdkConfiguration? _configuration;

  TestSdkConfigurationProvider({bool verboseCompiler = false})
      : _verboseCompiler = verboseCompiler;

  @override
  Future<SdkConfiguration> get configuration async =>
      _configuration ??= await _create();

  /// Generate missing assets in the default SDK layout.
  Future<SdkConfiguration> _create() async {
    final sdk = SdkConfiguration.defaultConfiguration;
    final sdkLayout = SdkConfiguration.defaultSdkLayout;

    final assetGenerator = SdkAssetGenerator(
      sdkLayout: sdkLayout,
      verboseCompiler: _verboseCompiler,
    );

    if (sdkLayout.soundSummaryPath != sdk.soundSdkSummaryPath) {
      throw StateError('Invalid asset path ${sdkLayout.soundSummaryPath}');
    }
    if (sdkLayout.weakSummaryPath != sdk.weakSdkSummaryPath) {
      throw StateError('Invalid asset path ${sdkLayout.weakSummaryPath}');
    }

    await assetGenerator.generateSdkAssets();
    return sdk;
  }
}
