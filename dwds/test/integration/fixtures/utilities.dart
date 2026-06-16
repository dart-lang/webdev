// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @skip_package_deps_validation

import 'dart:async';
import 'dart:convert';
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
  void Function(ServerLog) logHandler,
) async {
  final process = await Process.start(dartPath, [
    'run',
    'build_runner',
    'daemon',
    ...options,
  ], workingDirectory: workingDirectory);

  final stdoutBuffer = <String>[];
  final stderrBuffer = <String>[];
  final daemonStartup = Completer<String>();

  process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (line) {
      stdoutBuffer.add(line);
      if (line == readyToConnectLog ||
          line == versionSkew ||
          line == optionsSkew) {
        if (!daemonStartup.isCompleted) {
          daemonStartup.complete(line);
        }
      }
    },
  );

  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderrBuffer.add(line));

  final result = await Future.any([
    daemonStartup.future,
    Future.delayed(
      const Duration(seconds: 45),
      () => 'Timed out waiting for daemon to start up.',
    ),
  ]);

  if (result == readyToConnectLog) {
    return BuildDaemonClient.connectUnchecked(
      workingDirectory,
      logHandler: logHandler,
    );
  }

  process.kill();
  final exitCode = await process.exitCode.timeout(
    const Duration(seconds: 5),
    onTimeout: () => -1,
  );

  final details = [
    'Command: dart run build_runner daemon ${options.join(' ')}',
    'Working Directory: $workingDirectory',
    'Exit Code: $exitCode',
    if (stdoutBuffer.isNotEmpty) 'Stdout:\n${stdoutBuffer.join('\n')}',
    if (stderrBuffer.isNotEmpty) 'Stderr:\n${stderrBuffer.join('\n')}',
  ].join('\n');

  throw StateError('Failed to start build daemon (result: $result).\n$details');
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

class TestDebugSettings extends DebugSettings {
  TestDebugSettings.withDevToolsLaunch(
    TestContext context, {
    bool serveFromDds = false,
  }) : super(
         // ignore: deprecated_member_use_from_same_package
         devToolsLauncher: serveFromDds
             ? null
             : (hostname) async {
                 final server = await DevToolsServer().serveDevTools(
                   hostname: hostname,
                   enableStdinCommands: false,
                   customDevToolsPath: context
                       .sdkConfigurationProvider
                       .sdkLayout
                       .devToolsDirectory,
                 );
                 if (server == null) {
                   throw StateError('DevTools server could not be started.');
                 }
                 return DevTools(server.address.host, server.port, server);
               },
         ddsConfiguration: DartDevelopmentServiceConfiguration(
           serveDevTools: serveFromDds,
         ),
       );

  const TestDebugSettings.noDevToolsLaunch()
    : super(enableDevToolsLaunch: false);

  TestDebugSettings._({
    required super.enableDebugging,
    required super.enableDebugExtension,
    required super.useSseForDebugBackend,
    required super.useSseForDebugProxy,
    required super.useSseForInjectedClient,
    required super.spawnDds,
    required super.ddsPort,
    required super.enableDevToolsLaunch,
    required super.launchDevToolsInNewWindow,
    required super.emitDebugEvents,
    required super.devToolsLauncher,
    required super.expressionCompiler,
    required super.urlEncoder,
    required super.ddsConfiguration,
  });

  TestDebugSettings copyWith({
    bool? enableDebugging,
    bool? enableDebugExtension,
    bool? useSse,
    bool? spawnDds,
    int? ddsPort,
    bool? enableDevToolsLaunch,
    bool? launchDevToolsInNewWindow,
    bool? emitDebugEvents,
    DevToolsLauncher? devToolsLauncher,
    ExpressionCompiler? expressionCompiler,
    UrlEncoder? urlEncoder,
    DartDevelopmentServiceConfiguration? ddsConfiguration,
  }) {
    return TestDebugSettings._(
      enableDebugging: enableDebugging ?? this.enableDebugging,
      enableDebugExtension: enableDebugExtension ?? this.enableDebugExtension,
      useSseForDebugProxy: useSse ?? useSseForDebugProxy,
      useSseForDebugBackend: useSse ?? useSseForDebugBackend,
      useSseForInjectedClient: useSse ?? useSseForInjectedClient,
      // ignore: deprecated_member_use_from_same_package
      spawnDds: spawnDds ?? this.spawnDds,
      // ignore: deprecated_member_use_from_same_package
      ddsPort: ddsPort ?? this.ddsPort,
      enableDevToolsLaunch: enableDevToolsLaunch ?? this.enableDevToolsLaunch,
      launchDevToolsInNewWindow:
          launchDevToolsInNewWindow ?? this.launchDevToolsInNewWindow,
      emitDebugEvents: emitDebugEvents ?? this.emitDebugEvents,
      // ignore: deprecated_member_use_from_same_package
      devToolsLauncher: devToolsLauncher ?? this.devToolsLauncher,
      expressionCompiler: expressionCompiler ?? this.expressionCompiler,
      urlEncoder: urlEncoder ?? this.urlEncoder,
      ddsConfiguration: ddsConfiguration ?? this.ddsConfiguration,
    );
  }
}

class TestAppMetadata extends AppMetadata {
  const TestAppMetadata({
    super.isInternalBuild,
    super.workspaceName,
    super.hostname = 'localhost',
  });

  TestAppMetadata copyWith({
    bool? isFlutterApp,
    bool? isInternalBuild,
    String? workspaceName,
    String? hostname,
  }) => TestAppMetadata(
    isInternalBuild: isInternalBuild ?? this.isInternalBuild,
    workspaceName: workspaceName ?? this.workspaceName,
    hostname: hostname ?? this.hostname,
  );

  const TestAppMetadata.externalApp() : super(isInternalBuild: false);

  const TestAppMetadata.internalApp() : super(isInternalBuild: true);
}

class TestToolConfiguration extends ToolConfiguration {
  TestToolConfiguration.withDefaultLoadStrategy({
    TestAppMetadata super.appMetadata = const TestAppMetadata.externalApp(),
    TestDebugSettings super.debugSettings =
        const TestDebugSettings.noDevToolsLaunch(),
    TestBuildSettings buildSettings = const TestBuildSettings.dart(),
  }) : super(loadStrategy: TestStrategy(FakeAssetReader(), buildSettings));

  TestToolConfiguration.withLoadStrategy({
    TestAppMetadata super.appMetadata = const TestAppMetadata.externalApp(),
    TestDebugSettings super.debugSettings =
        const TestDebugSettings.noDevToolsLaunch(),
    required super.loadStrategy,
  });
}

void setGlobalsForTesting({ToolConfiguration? toolConfiguration}) {
  globalToolConfiguration =
      toolConfiguration ?? TestToolConfiguration.withDefaultLoadStrategy();
}

void setGlobalsForTestingFromBuild({
  TestBuildSettings buildSettings = const TestBuildSettings.dart(),
}) {
  globalToolConfiguration = TestToolConfiguration.withDefaultLoadStrategy(
    buildSettings: buildSettings,
  );
}

class TestStrategy extends FakeStrategy {
  TestStrategy(super.assetReader, BuildSettings buildSettings)
    : super(buildSettings: buildSettings);

  @override
  String serverPathForAppUri(String appUri) {
    return 'foo';
  }
}

/// Settings defining how to run the tests.
class TestSettings {
  // Scenario settings.
  final ReloadConfiguration reloadConfiguration;
  final bool autoRun;
  final bool waitToDebug;
  final bool enableExpressionEvaluation;
  final bool verboseCompiler;
  final bool launchChrome;

  // Build settings.
  final CompilationMode compilationMode;
  final ModuleFormat moduleFormat;
  final bool canaryFeatures;
  final bool isFlutterApp;
  final List<String> experiments;
  final bool useDebuggerModuleNames;

  const TestSettings({
    this.reloadConfiguration = ReloadConfiguration.none,
    this.autoRun = true,
    this.waitToDebug = false,
    this.enableExpressionEvaluation = false,
    this.verboseCompiler = false,
    this.launchChrome = true,
    this.compilationMode = CompilationMode.buildDaemon,
    this.moduleFormat = ModuleFormat.amd,
    this.canaryFeatures = false,
    this.isFlutterApp = false,
    this.experiments = const <String>[],
    this.useDebuggerModuleNames = false,
  });
}

/// App build settings for tests.
class TestBuildSettings extends BuildSettings {
  const TestBuildSettings({
    super.appEntrypoint,
    super.canaryFeatures,
    super.isFlutterApp,
    super.experiments,
  });

  const TestBuildSettings.dart({Uri? appEntrypoint})
    : this(appEntrypoint: appEntrypoint, isFlutterApp: false);

  const TestBuildSettings.flutter({Uri? appEntrypoint})
    : this(appEntrypoint: appEntrypoint, isFlutterApp: true);

  TestBuildSettings copyWith({
    Uri? appEntrypoint,
    bool? canaryFeatures,
    bool? isFlutterApp,
    List<String>? experiments,
  }) => TestBuildSettings(
    appEntrypoint: appEntrypoint ?? this.appEntrypoint,
    canaryFeatures: canaryFeatures ?? this.canaryFeatures,
    isFlutterApp: isFlutterApp ?? this.isFlutterApp,
    experiments: experiments ?? this.experiments,
  );
}

class TestCompilerOptions extends CompilerOptions {
  TestCompilerOptions({
    required super.canaryFeatures,
    super.experiments = const <String>[],
    super.moduleFormat = ModuleFormat.amd,
  });
}
