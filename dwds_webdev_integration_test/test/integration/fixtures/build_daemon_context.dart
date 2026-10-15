// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/build_status.dart' as daemon;
import 'package:build_daemon/data/build_target.dart';
import 'package:dwds/asset_reader.dart';
import 'package:dwds/data/build_result.dart';
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/loaders/build_runner_strategy_provider.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/readers/proxy_server_asset_reader.dart';
import 'package:dwds/src/services/expression_compiler_service.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/fixtures/utilities.dart';
import 'package:logging/logging.dart' as logging;
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

/// A [TestContext] that builds and serves the test app with `build_runner`,
/// through the build daemon.
class BuildDaemonTestContext extends TestContext {
  BuildDaemonClient? _daemonClient;
  ExpressionCompilerService? _expressionCompilerService;
  AssetReader? _assetReader;
  Handler? _assetHandler;
  LoadStrategy? _loadStrategy;
  Stream<BuildResult>? _buildResults;

  final _logger = logging.Logger('BuildDaemonContext');

  BuildDaemonTestContext(super.project, super.sdkConfigurationProvider)
    : super.protected();

  @override
  String get appUrlPath => project.filePathToServe;

  @override
  bool get usesBuildDaemon => true;

  BuildDaemonClient get daemonClient => _daemonClient!;

  @override
  AssetReader get assetReader => _assetReader!;

  @override
  Handler get assetHandler => _assetHandler!;

  @override
  LoadStrategy get loadStrategy => _loadStrategy!;

  @override
  ExpressionCompiler? get expressionCompiler => _expressionCompilerService;

  @override
  Stream<BuildResult> get buildResults => _buildResults!;

  @override
  Future<void> modeSetUp(
    TestSettings testSettings,
    TestDebugSettings debugSettings,
    TestAppMetadata appMetadata,
    Uri reloadedSourcesUri,
  ) async {
    final buildSettings = TestBuildSettings(
      appEntrypoint: project.dartEntryFilePackageUri,
      canaryFeatures: testSettings.canaryFeatures,
      isFlutterApp: testSettings.isFlutterApp,
      experiments: testSettings.experiments,
    );

    _daemonClient = await _connectDaemonClient(testSettings, buildSettings);
    daemonClient
      ..registerBuildTarget(
        DefaultBuildTarget((b) => b..target = project.directoryToServe),
      )
      ..startBuild();
    _buildResults = _toDwdsBuildResults(daemonClient.buildResults);

    await waitForSuccessfulBuild();

    final assetServerPort = _daemonAssetServerPort();
    _assetHandler = _createAssetHandler(
      assetServerPort,
      serveReloadedSources: _usesDdcLibraryBundle(testSettings),
    );
    _assetReader = ProxyServerAssetReader(
      assetServerPort,
      root: project.directoryToServe,
    );

    if (testSettings.enableExpressionEvaluation) {
      _expressionCompilerService = ExpressionCompilerService(
        'localhost',
        port,
        verbose: testSettings.verboseCompiler,
        sdkConfigurationProvider: sdkConfigurationProvider,
      );
    }

    _loadStrategy = _createLoadStrategy(
      testSettings,
      buildSettings,
      reloadedSourcesUri,
    );
  }

  @override
  Future<void> modeTearDown() async {
    await _daemonClient?.close();
    await _expressionCompilerService?.stop();
    _daemonClient = null;
    _expressionCompilerService = null;
    _assetReader = null;
    _assetHandler = null;
    _loadStrategy = null;
    _buildResults = null;
  }

  @override
  Future<void> waitForSuccessfulBuild({
    Duration? timeout,
    bool propagateToBrowser = false,
    bool allowFailure = false,
  }) async {
    final status = await _targetBuildStatuses(daemonClient.buildResults)
        .firstWhere(
          (status) =>
              status == daemon.BuildStatus.succeeded ||
              (allowFailure && status == daemon.BuildStatus.failed),
        )
        .timeout(timeout ?? const Duration(seconds: 60));
    lastBuildFailed = status == daemon.BuildStatus.failed;

    if (propagateToBrowser) {
      // Allow change to propagate to the browser.
      // Windows, or at least Travis on Windows, seems to need more time.
      // TODO: Wait for an explicit finish signal instead of adding this delay.
      final delay = Platform.isWindows
          ? const Duration(seconds: 5)
          : const Duration(seconds: 2);
      await Future<void>.delayed(delay);
    }
  }

  /// Starts a build daemon for the test project and connects to it.
  Future<BuildDaemonClient> _connectDaemonClient(
    TestSettings testSettings,
    TestBuildSettings buildSettings,
  ) => BuildDaemonClient.connect(
    project.absolutePackageDirectory,
    [
      sdkConfigurationProvider.sdkLayout.dartPath,
      'run',
      'build_runner',
      'daemon',
      ..._buildRunnerOptions(testSettings, buildSettings),
    ],
    logHandler: (log) {
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

  /// The `build_runner daemon` options matching [testSettings].
  List<String> _buildRunnerOptions(
    TestSettings testSettings,
    TestBuildSettings buildSettings,
  ) => [
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

  /// Returns the port of the build daemon's asset server.
  int _daemonAssetServerPort() {
    final portFile = File(
      '${daemonWorkspace(project.absolutePackageDirectory)}'
      '/.asset_server_port',
    );
    if (!portFile.existsSync()) {
      throw StateError('Unable to read daemon asset port file.');
    }
    return int.parse(portFile.readAsStringSync());
  }

  /// Creates a handler that proxies asset requests to the build daemon's
  /// asset server.
  ///
  /// If [serveReloadedSources] is true, requests for the reloaded sources
  /// manifest are served by this context instead.
  Handler _createAssetHandler(
    int assetServerPort, {
    required bool serveReloadedSources,
  }) {
    final proxy = proxyHandler(
      'http://localhost:$assetServerPort/${project.directoryToServe}/',
      client: client,
    );
    return serveReloadedSources ? handleReloadedSources(proxy) : proxy;
  }

  LoadStrategy _createLoadStrategy(
    TestSettings testSettings,
    TestBuildSettings buildSettings,
    Uri reloadedSourcesUri,
  ) => switch ((testSettings.moduleFormat, buildSettings.canaryFeatures)) {
    (ModuleFormat.ddc, true) => BuildRunnerDdcLibraryBundleStrategyProvider(
      testSettings.reloadConfiguration,
      assetReader,
      buildSettings,
      reloadedSourcesUri: reloadedSourcesUri,
    ).strategy,
    (ModuleFormat.ddc, false) => throw UnsupportedError(
      'Unsupported DDC configuration: build daemon + canary (false) '
      '+ DDC module format ${testSettings.moduleFormat.name}.',
    ),
    _ => BuildRunnerRequireStrategyProvider(
      testSettings.reloadConfiguration,
      assetReader,
      buildSettings,
    ).strategy,
  };

  /// Converts build daemon results into the [BuildResult]s DWDS expects,
  /// keeping only results for the target being served.
  Stream<BuildResult> _toDwdsBuildResults(
    Stream<daemon.BuildResults> results,
  ) => _targetBuildStatuses(results).map(
    (status) => switch (status) {
      daemon.BuildStatus.started => BuildResult(status: BuildStatus.started),
      daemon.BuildStatus.failed => BuildResult(status: BuildStatus.failed),
      daemon.BuildStatus.succeeded => BuildResult(
        status: BuildStatus.succeeded,
      ),
      _ => throw StateError('Unexpected daemon build status: $status'),
    },
  );

  /// The build statuses for the target being served.
  Stream<daemon.BuildStatus> _targetBuildStatuses(
    Stream<daemon.BuildResults> results,
  ) => results.expand(
    (results) => [
      for (final result in results.results)
        if (result.target == project.directoryToServe) result.status,
    ],
  );

  static bool _usesDdcLibraryBundle(TestSettings testSettings) =>
      testSettings.moduleFormat == ModuleFormat.ddc &&
      testSettings.canaryFeatures;
}
