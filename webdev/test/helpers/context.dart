// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/build_status.dart' as daemon;
import 'package:build_daemon/data/build_target.dart';
import 'package:build_daemon/data/server_log.dart';
import 'package:dwds/asset_reader.dart';
import 'package:dwds/data/build_result.dart' as dwds;
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/loaders/build_runner_strategy_provider.dart';
import 'package:dwds/src/loaders/frontend_server_strategy_provider.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/readers/proxy_server_asset_reader.dart';
import 'package:dwds/src/services/expression_compiler_service.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/fixtures/utilities.dart';
import 'package:file/local.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart' as logging;
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

Handler createBuildRunnerProxyHandler({
  required String directoryToServe,
  required Client client,
  required int assetServerPort,
}) {
  return proxyHandler(
    'http://localhost:$assetServerPort/$directoryToServe/',
    client: client,
  );
}

class BuildDaemonTestContext extends TestContext {
  final _logger = logging.Logger('BuildDaemonTestContext');

  BuildDaemonTestContext(super.project, super.sdkConfigurationProvider)
    : super.protected();

  late AssetReader _assetReader;
  late Handler _assetHandler;
  late LoadStrategy _loadStrategy;
  late Stream<dwds.BuildResult> _buildResults;
  ExpressionCompiler? _expressionCompiler;

  late BuildDaemonClient daemonClient;
  ExpressionCompilerService? ddcService;

  @override
  AssetReader get assetReader => _assetReader;
  @override
  Handler get assetHandler => _assetHandler;
  @override
  LoadStrategy get loadStrategy => _loadStrategy;
  @override
  Stream<dwds.BuildResult> get buildResults => _buildResults;
  @override
  ExpressionCompiler? get expressionCompiler => _expressionCompiler;

  @override
  bool get usesFrontendServer => false;
  @override
  bool get usesBuildDaemon => true;
  @override
  bool get usesDdcModulesOnly => false;

  @override
  String get appUrlPath => project.filePathToServe;

  @override
  Future<void> modeSetUp(
    TestSettings testSettings,
    TestDebugSettings debugSettings,
    TestAppMetadata appMetadata,
    Uri reloadedSourcesUri,
  ) async {
    final sdkLayout = sdkConfigurationProvider.sdkLayout;
    final buildSettings = TestBuildSettings(
      appEntrypoint: project.dartEntryFilePackageUri,
      canaryFeatures: testSettings.canaryFeatures,
      isFlutterApp: testSettings.isFlutterApp,
      experiments: testSettings.experiments,
    );

    final options = [
      if (testSettings.enableExpressionEvaluation) ...[
        '--define',
        'build_web_compilers|ddc=generate-full-dill=true',
      ],
      for (final experiment in buildSettings.experiments)
        '--enable-experiment=$experiment',
      if (buildSettings.canaryFeatures) ...[
        '--define',
        'build_web_compilers|ddc=canary=true',
        '--define',
        'build_web_compilers|sdk_js=canary=true',
      ],
      if (testSettings.moduleFormat == ModuleFormat.ddc) ...[
        '--define',
        'build_web_compilers|ddc=ddc-library-bundle=true',
        '--define',
        'build_web_compilers|sdk_js=ddc-library-bundle=true',
        '--define',
        'build_web_compilers|entrypoint=ddc-library-bundle=true',
        '--define',
        'build_web_compilers|entrypoint_marker=ddc-library-bundle=true',
      ],
      '--verbose',
    ];
    daemonClient = await connectClient(
      sdkLayout.dartPath,
      project.absolutePackageDirectory,
      options,
      (log) {
        final record = log.toLogRecord();
        final name = record.loggerName == '' ? '' : '${record.loggerName}: ';
        _logger.log(
          record.level,
          '$name${record.message}',
          record.error,
          record.stackTrace,
        );
      },
    );
    daemonClient.registerBuildTarget(
      DefaultBuildTarget((b) => b..target = project.directoryToServe),
    );
    daemonClient.startBuild();

    await waitForSuccessfulBuild();

    final assetServerPort = daemonPort(project.absolutePackageDirectory);
    _assetHandler = createBuildRunnerProxyHandler(
      directoryToServe: project.directoryToServe,
      client: client,
      assetServerPort: assetServerPort,
    );
    if (testSettings.moduleFormat == ModuleFormat.ddc &&
        buildSettings.canaryFeatures) {
      _assetHandler = handleReloadedSources(_assetHandler);
    }
    _assetReader = ProxyServerAssetReader(
      assetServerPort,
      root: project.directoryToServe,
    );

    if (testSettings.enableExpressionEvaluation) {
      ddcService = ExpressionCompilerService(
        'localhost',
        port,
        verbose: testSettings.verboseCompiler,
        sdkConfigurationProvider: sdkConfigurationProvider,
      );
      _expressionCompiler = ddcService;
    }

    _loadStrategy = switch ((
      testSettings.moduleFormat,
      buildSettings.canaryFeatures,
    )) {
      (ModuleFormat.ddc, true) => BuildRunnerDdcLibraryBundleStrategyProvider(
        testSettings.reloadConfiguration,
        _assetReader,
        buildSettings,
        reloadedSourcesUri: reloadedSourcesUri,
      ).strategy,
      (ModuleFormat.ddc, false) => throw Exception(
        'Unsupported DDC configuration: build daemon + canary (false) '
        '+ DDC module format ${testSettings.moduleFormat.name}.',
      ),
      _ => BuildRunnerRequireStrategyProvider(
        testSettings.reloadConfiguration,
        _assetReader,
        buildSettings,
      ).strategy,
    };

    _buildResults = daemonClient.buildResults.map((results) {
      final result = results.results.firstWhere(
        (result) => result.target == project.directoryToServe,
      );
      switch (result.status) {
        case daemon.BuildStatus.started:
          return dwds.BuildResult(status: dwds.BuildStatus.started);
        case daemon.BuildStatus.failed:
          return dwds.BuildResult(status: dwds.BuildStatus.failed);
        case daemon.BuildStatus.succeeded:
          return dwds.BuildResult(status: dwds.BuildStatus.succeeded);
      }
      throw StateError('Unexpected Daemon build result: $result');
    });
  }

  @override
  Future<void> modeTearDown() async {
    await ddcService?.stop();
    await daemonClient.close();
  }
}

class BuildDaemonAndFrontendServerTestContext extends TestContext {
  final _logger = logging.Logger('BuildDaemonAndFrontendServerTestContext');

  BuildDaemonAndFrontendServerTestContext(
    super.project,
    super.sdkConfigurationProvider,
  ) : super.protected();

  late AssetReader _assetReader;
  late Handler _assetHandler;
  late LoadStrategy _loadStrategy;
  late Stream<dwds.BuildResult> _buildResults;
  ExpressionCompiler? _expressionCompiler;

  late BuildDaemonClient daemonClient;
  ExpressionCompilerService? ddcService;
  late LocalFileSystem frontendServerFileSystem;

  @override
  AssetReader get assetReader => _assetReader;
  @override
  Handler get assetHandler => _assetHandler;
  @override
  LoadStrategy get loadStrategy => _loadStrategy;
  @override
  Stream<dwds.BuildResult> get buildResults => _buildResults;
  @override
  ExpressionCompiler? get expressionCompiler => _expressionCompiler;

  @override
  bool get usesFrontendServer => true;
  @override
  bool get usesBuildDaemon => true;
  @override
  bool get usesDdcModulesOnly => true;

  @override
  String get appUrlPath => project.filePathToServe;

  @override
  Future<void> modeSetUp(
    TestSettings testSettings,
    TestDebugSettings debugSettings,
    TestAppMetadata appMetadata,
    Uri reloadedSourcesUri,
  ) async {
    final sdkLayout = sdkConfigurationProvider.sdkLayout;
    final buildSettings = TestBuildSettings(
      appEntrypoint: project.dartEntryFilePackageUri,
      canaryFeatures: testSettings.canaryFeatures,
      isFlutterApp: testSettings.isFlutterApp,
      experiments: testSettings.experiments,
    );

    final options = [
      if (testSettings.enableExpressionEvaluation) ...[
        '--define',
        'build_web_compilers|ddc=generate-full-dill=true',
      ],
      for (final experiment in buildSettings.experiments)
        '--enable-experiment=$experiment',
      '--define',
      'build_web_compilers|ddc=canary=true',
      '--define',
      'build_web_compilers|sdk_js=canary=true',
      '--define',
      'build_web_compilers|sdk_js=web-hot-reload=true',
      '--define',
      'build_web_compilers|entrypoint=web-hot-reload=true',
      '--define',
      'build_web_compilers|entrypoint_marker=web-hot-reload=true',
      '--define',
      'build_web_compilers|entrypoint_marker=web-assets-path='
          '${project.webAssetsPath}',
      '--define',
      'build_web_compilers|ddc=web-hot-reload=true',
      '--define',
      'build_web_compilers|ddc_modules=web-hot-reload=true',
      '--verbose',
    ];
    daemonClient = await connectClient(
      sdkLayout.dartPath,
      project.absolutePackageDirectory,
      options,
      (log) {
        final record = log.toLogRecord();
        final name = record.loggerName == '' ? '' : '${record.loggerName}: ';
        _logger.log(
          record.level,
          '$name${record.message}',
          record.error,
          record.stackTrace,
        );
      },
    );
    daemonClient.registerBuildTarget(
      DefaultBuildTarget((b) => b..target = project.directoryToServe),
    );
    daemonClient.startBuild();

    await waitForSuccessfulBuild();

    final assetServerPort = daemonPort(project.absolutePackageDirectory);
    _assetHandler = createBuildRunnerProxyHandler(
      directoryToServe: project.directoryToServe,
      client: client,
      assetServerPort: assetServerPort,
    );
    if (testSettings.moduleFormat == ModuleFormat.ddc &&
        buildSettings.canaryFeatures) {
      _assetHandler = handleReloadedSources(_assetHandler);
    }
    _assetReader = ProxyServerAssetReader(
      assetServerPort,
      root: project.directoryToServe,
    );

    if (testSettings.enableExpressionEvaluation) {
      ddcService = ExpressionCompilerService(
        'localhost',
        port,
        verbose: testSettings.verboseCompiler,
        sdkConfigurationProvider: sdkConfigurationProvider,
      );
      _expressionCompiler = ddcService;
    }
    frontendServerFileSystem = const LocalFileSystem();
    final packageUriMapper = await PackageUriMapper.create(
      frontendServerFileSystem,
      project.packageConfigFile,
      useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
    );
    _loadStrategy = switch ((
      testSettings.moduleFormat,
      buildSettings.canaryFeatures,
    )) {
      (ModuleFormat.ddc, true) =>
        FrontendServerDdcLibraryBundleStrategyProvider(
          testSettings.reloadConfiguration,
          _assetReader,
          packageUriMapper,
          () async => {},
          buildSettings,
          injectScriptLoad: false,
          reloadedSourcesUri: reloadedSourcesUri,
        ).strategy,
      _ => throw Exception(
        'Unsupported DDC module format when compiling with Frontend '
        'Server + build_runner ${testSettings.moduleFormat.name}.',
      ),
    };
    _buildResults = const Stream<dwds.BuildResult>.empty();
  }

  @override
  Future<void> modeTearDown() async {
    await ddcService?.stop();
    await daemonClient.close();
  }
}

/// Connects to the `build_runner` daemon.
Future<BuildDaemonClient> connectClient(
  String dartPath,
  String workingDirectory,
  List<String> options,
  void Function(ServerLog) logHandler,
) => BuildDaemonClient.connect(workingDirectory, [
  dartPath,
  'run',
  'build_runner',
  'daemon',
  ...options,
], logHandler: logHandler);

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
