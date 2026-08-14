import 'package:build_daemon/data/build_status.dart' as daemon;
import 'package:build_daemon/data/build_target.dart';
import 'package:dwds/asset_reader.dart';
import 'package:dwds/data/build_result.dart' as dwds;
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/loaders/build_runner_strategy_provider.dart';
import 'package:dwds/src/loaders/frontend_server_strategy_provider.dart';
import 'package:dwds/src/readers/proxy_server_asset_reader.dart';
import 'package:dwds/src/services/expression_compiler_service.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/fixtures/utilities.dart';
import 'package:file/local.dart';
import 'package:logging/logging.dart' as logging;

class BuildDaemonTestContext extends TestContext {
  final _logger = logging.Logger('BuildDaemonTestContext');

  BuildDaemonTestContext(super.project, super.sdkConfigurationProvider);

  @override
  bool get usesFrontendServer => false;
  @override
  bool get usesBuildDaemon => true;
  @override
  bool get usesDdcModulesOnly => false;

  @override
  Future<void> modeSetUp({
    required TestSettings testSettings,
    required TestAppMetadata appMetadata,
    required TestDebugSettings debugSettings,
    required TestBuildSettings buildSettings,
    required Uri reloadedSourcesUri,
  }) async {
    final sdkLayout = sdkConfigurationProvider.sdkLayout;

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
    assetHandler = createBuildRunnerProxyHandler(assetServerPort);
    if (testSettings.moduleFormat == ModuleFormat.ddc &&
        buildSettings.canaryFeatures) {
      assetHandler = handleReloadedSources(assetHandler);
    }
    assetReader = ProxyServerAssetReader(
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
      expressionCompiler = ddcService;
    }

    loadStrategy = switch ((
      testSettings.moduleFormat,
      buildSettings.canaryFeatures,
    )) {
      (ModuleFormat.ddc, true) => BuildRunnerDdcLibraryBundleStrategyProvider(
        testSettings.reloadConfiguration,
        assetReader,
        buildSettings,
        reloadedSourcesUri: reloadedSourcesUri,
      ).strategy,
      (ModuleFormat.ddc, false) => throw Exception(
        'Unsupported DDC configuration: build daemon + canary (false) '
        '+ DDC module format ${testSettings.moduleFormat.name}.',
      ),
      _ => BuildRunnerRequireStrategyProvider(
        testSettings.reloadConfiguration,
        assetReader,
        buildSettings,
      ).strategy,
    };

    buildResults = daemonClient.buildResults.map((results) {
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
}

class BuildDaemonAndFrontendServerTestContext extends TestContext {
  final _logger = logging.Logger('BuildDaemonAndFrontendServerTestContext');

  BuildDaemonAndFrontendServerTestContext(
    super.project,
    super.sdkConfigurationProvider,
  );

  @override
  bool get usesFrontendServer => true;
  @override
  bool get usesBuildDaemon => true;
  @override
  bool get usesDdcModulesOnly => true;

  @override
  Future<void> modeSetUp({
    required TestSettings testSettings,
    required TestAppMetadata appMetadata,
    required TestDebugSettings debugSettings,
    required TestBuildSettings buildSettings,
    required Uri reloadedSourcesUri,
  }) async {
    final sdkLayout = sdkConfigurationProvider.sdkLayout;

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
    assetHandler = createBuildRunnerProxyHandler(assetServerPort);
    if (testSettings.moduleFormat == ModuleFormat.ddc &&
        buildSettings.canaryFeatures) {
      assetHandler = handleReloadedSources(assetHandler);
    }
    assetReader = ProxyServerAssetReader(
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
      expressionCompiler = ddcService;
    }
    frontendServerFileSystem = const LocalFileSystem();
    final packageUriMapper = await PackageUriMapper.create(
      frontendServerFileSystem,
      project.packageConfigFile,
      useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
    );
    loadStrategy = switch ((
      testSettings.moduleFormat,
      buildSettings.canaryFeatures,
    )) {
      (ModuleFormat.ddc, true) =>
        FrontendServerDdcLibraryBundleStrategyProvider(
          testSettings.reloadConfiguration,
          assetReader,
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
    buildResults = const Stream<dwds.BuildResult>.empty();
  }
}
