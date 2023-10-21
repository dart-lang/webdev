// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:dds/devtools_server.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/servers/devtools.dart';
import 'package:dwds/src/services/expression_compiler.dart';

import 'context.dart';
import 'fakes.dart';

/// Connects to the `build_runner` daemon.
Future<BuildDaemonClient> connectClient(
  String dartPath,
  String workingDirectory,
  List<String> options,
  Function(ServerLog) logHandler,
) =>
    BuildDaemonClient.connect(
      workingDirectory,
      [dartPath, 'run', 'build_runner', 'daemon', ...options],
      logHandler: logHandler,
    );

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

class TestDebugSettings extends DebugSettings {
  TestDebugSettings.withDevTools(TestContext context)
      : super(
          devToolsLauncher: (hostname) async {
            final server = await DevToolsServer().serveDevTools(
              hostname: hostname,
              enableStdinCommands: false,
              customDevToolsPath:
                  context.sdkConfigurationProvider.sdkLayout.devToolsDirectory,
            );
            if (server == null) {
              throw StateError('DevTools server could not be started.');
            }
            return DevTools(server.address.host, server.port, server);
          },
        );

  TestDebugSettings.noDevTools() : super(enableDevToolsLaunch: false);

  TestDebugSettings._({
    required super.enableDebugging,
    required super.enableDebugExtension,
    required super.useSseForDebugBackend,
    required super.useSseForDebugProxy,
    required super.useSseForInjectedClient,
    required super.spawnDds,
    required super.enableDevToolsLaunch,
    required super.launchDevToolsInNewWindow,
    required super.emitDebugEvents,
    required super.devToolsLauncher,
    required super.expressionCompiler,
    required super.urlEncoder,
  });

  TestDebugSettings copyWith({
    bool? enableDebugging,
    bool? enableDebugExtension,
    bool? useSse,
    bool? spawnDds,
    bool? enableDevToolsLaunch,
    bool? launchDevToolsInNewWindow,
    bool? emitDebugEvents,
    DevToolsLauncher? devToolsLauncher,
    ExpressionCompiler? expressionCompiler,
    UrlEncoder? urlEncoder,
  }) {
    return TestDebugSettings._(
      enableDebugging: enableDebugging ?? this.enableDebugging,
      enableDebugExtension: enableDebugExtension ?? this.enableDebugExtension,
      useSseForDebugProxy: useSse ?? useSseForDebugProxy,
      useSseForDebugBackend: useSse ?? useSseForDebugBackend,
      useSseForInjectedClient: useSse ?? useSseForInjectedClient,
      spawnDds: spawnDds ?? this.spawnDds,
      enableDevToolsLaunch: enableDevToolsLaunch ?? this.enableDevToolsLaunch,
      launchDevToolsInNewWindow:
          launchDevToolsInNewWindow ?? this.launchDevToolsInNewWindow,
      emitDebugEvents: emitDebugEvents ?? this.emitDebugEvents,
      devToolsLauncher: devToolsLauncher ?? this.devToolsLauncher,
      expressionCompiler: expressionCompiler ?? this.expressionCompiler,
      urlEncoder: urlEncoder ?? this.urlEncoder,
    );
  }
}

class TestAppMetadata extends AppMetadata {
  TestAppMetadata.internalFlutterApp()
      : super(
          isFlutterApp: () => Future.value(true),
          isInternalBuild: true,
        );
  TestAppMetadata.internalDartApp()
      : super(
          isFlutterApp: () => Future.value(false),
          isInternalBuild: true,
        );
  TestAppMetadata.externalFlutterApp()
      : super(
          isFlutterApp: () => Future.value(true),
          isInternalBuild: false,
        );
  TestAppMetadata.externalDartApp()
      : super(
          isFlutterApp: () => Future.value(false),
          isInternalBuild: false,
        );
}

class TestToolConfiguration extends ToolConfiguration {
  TestToolConfiguration.forTests({
    LoadStrategy? loadStrategy,
    DebugSettings? debugSettings,
    AppMetadata? appMetadata,
  }) : super(
          loadStrategy: loadStrategy ?? FakeStrategy(FakeAssetReader()),
          debugSettings: debugSettings ?? TestDebugSettings.noDevTools(),
          appMetadata: appMetadata ?? TestAppMetadata.externalDartApp(),
        );
}

void setGlobalsForTesting({
  ToolConfiguration? toolConfiguration,
}) {
  globalToolConfiguration =
      toolConfiguration ?? TestToolConfiguration.forTests();
}
