// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:dds/devtools_server.dart';
import 'package:dwds/asset_reader.dart';
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

  const TestDebugSettings.noDevTools() : super(enableDevToolsLaunch: false);

  const TestDebugSettings._({
    required bool enableDebugging,
    required bool enableDebugExtension,
    required bool useSseForDebugBackend,
    required bool useSseForDebugProxy,
    required bool useSseForInjectedClient,
    required bool spawnDds,
    required bool enableDevToolsLaunch,
    required bool launchDevToolsInNewWindow,
    required bool emitDebugEvents,
    required DevToolsLauncher? devToolsLauncher,
    required ExpressionCompiler? expressionCompiler,
    required UrlEncoder? urlEncoder,
  }) : super(
          enableDebugging: enableDebugging,
          enableDebugExtension: enableDebugExtension,
          useSseForDebugBackend: useSseForDebugBackend,
          useSseForDebugProxy: useSseForDebugProxy,
          useSseForInjectedClient: useSseForInjectedClient,
          spawnDds: spawnDds,
          enableDevToolsLaunch: enableDevToolsLaunch,
          launchDevToolsInNewWindow: launchDevToolsInNewWindow,
          emitDebugEvents: emitDebugEvents,
          devToolsLauncher: devToolsLauncher,
          expressionCompiler: expressionCompiler,
          urlEncoder: urlEncoder,
        );

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
  const TestAppMetadata({
    bool isInternalBuild = false,
    String? workspaceName,
    String hostname = 'localhost',
  }) : super(
          isInternalBuild: isInternalBuild,
          workspaceName: workspaceName,
          hostname: hostname,
        );

  TestAppMetadata copyWith({
    bool? isFlutterApp,
    bool? isInternalBuild,
    String? workspaceName,
    String? hostname = 'localhost',
  }) =>
      TestAppMetadata(
        isInternalBuild: isInternalBuild ?? this.isInternalBuild,
        workspaceName: workspaceName ?? this.workspaceName,
        hostname: hostname ?? this.hostname,
      );

  const TestAppMetadata.externalApp() : super(isInternalBuild: false);

  const TestAppMetadata.internalApp() : super(isInternalBuild: true);
}

class TestToolConfiguration extends ToolConfiguration {
  TestToolConfiguration.withDefaultLoadStrategy({
    TestSettings testSettings = const TestSettings(),
    TestAppMetadata appMetadata = const TestAppMetadata.externalApp(),
    TestDebugSettings debugSettings = const TestDebugSettings.noDevTools(),
    TestLoadStrategySettings loadStrategySettings =
        const TestLoadStrategySettings.dart(),
  }) : super(
          loadStrategy:
              TestStrategy(const FakeAssetReader(), loadStrategySettings),
          debugSettings: debugSettings,
          appMetadata: appMetadata,
        );

  TestToolConfiguration.withLoadStrategy({
    TestSettings testSettings = const TestSettings(),
    TestAppMetadata appMetadata = const TestAppMetadata.externalApp(),
    TestDebugSettings debugSettings = const TestDebugSettings.noDevTools(),
    required LoadStrategy loadStrategy,
  }) : super(
          loadStrategy: loadStrategy,
          debugSettings: debugSettings,
          appMetadata: appMetadata,
        );
}

void setGlobalsForTesting({
  ToolConfiguration? toolConfiguration,
}) {
  globalToolConfiguration =
      toolConfiguration ?? TestToolConfiguration.withDefaultLoadStrategy();
}

void createAndSetGlobalsForTesting({
  TestLoadStrategySettings loadStrategySettings =
      const TestLoadStrategySettings.dart(),
}) {
  globalToolConfiguration = TestToolConfiguration.withDefaultLoadStrategy(
    loadStrategySettings: loadStrategySettings,
  );
}

class TestStrategy extends FakeStrategy {
  TestStrategy(
    AssetReader assetReader,
    TestLoadStrategySettings settings,
  ) : super(
          assetReader,
          isFlutterApp: settings.isFlutterApp,
          canaryFeatures: settings.canaryFeatures,
        );

  @override
  String serverPathForAppUri(String appUri) {
    return 'foo';
  }
}

class TestLoadStrategySettings {
  final bool canaryFeatures;
  final bool isFlutterApp;

  const TestLoadStrategySettings({
    this.canaryFeatures = false,
    this.isFlutterApp = false,
  });

  const TestLoadStrategySettings.dart() : this(isFlutterApp: true);

  const TestLoadStrategySettings.flutter() : this(isFlutterApp: true);

  TestLoadStrategySettings copyWith({
    bool? isFlutterApp,
    bool? canaryFeatures,
  }) =>
      TestLoadStrategySettings(
        isFlutterApp: isFlutterApp ?? this.isFlutterApp,
        canaryFeatures: canaryFeatures ?? this.isFlutterApp,
      );
}

class TestSettings {
  /// Scenario settings.
  final ReloadConfiguration reloadConfiguration;
  final bool autoRun;
  final bool waitToDebug;
  final bool enableExpressionEvaluation;
  final bool verboseCompiler;
  final bool launchChrome;

  /// Build settings.
  final CompilationMode compilationMode;
  final List<String> experiments;
  final bool useDebuggerModuleNames;

  const TestSettings({
    this.reloadConfiguration = ReloadConfiguration.none,
    this.autoRun = true,
    this.waitToDebug = false,
    this.enableExpressionEvaluation = false,
    this.verboseCompiler = false,
    this.useDebuggerModuleNames = false,
    this.launchChrome = true,
    this.compilationMode = CompilationMode.buildDaemon,
    this.experiments = const <String>[],
  });
}
