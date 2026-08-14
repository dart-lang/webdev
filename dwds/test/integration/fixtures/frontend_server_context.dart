import 'dart:io';

import 'package:dwds/asset_reader.dart';
import 'package:dwds/data/build_result.dart' as dwds;
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/loaders/frontend_server_strategy_provider.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/fixtures/utilities.dart';
import 'package:dwds_test_common/frontend_server_common/resident_runner.dart';
import 'package:dwds_test_common/utilities.dart';
import 'package:file/local.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;

class FrontendServerTestContext extends TestContext {
  final _logger = logging.Logger('FrontendServerTestContext');

  FrontendServerTestContext(super.project, super.sdkConfigurationProvider);

  @override
  bool get usesFrontendServer => true;
  @override
  bool get usesBuildDaemon => false;
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
    filePathToServe = webCompatiblePath([
      project.directoryToServe,
      project.filePathToServe,
    ]);

    _logger.info('Serving: $filePathToServe');

    final entry = p.toUri(
      p.join(project.webAssetsPath, project.dartEntryFileName),
    );
    frontendServerFileSystem = const LocalFileSystem();
    final packageUriMapper = await FrontendServerPathResolver.create(
      frontendServerFileSystem,
      project.packageConfigFile,
      useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
    );

    final compilerOptions = TestCompilerOptions(
      experiments: buildSettings.experiments,
      canaryFeatures: buildSettings.canaryFeatures,
      moduleFormat: testSettings.moduleFormat,
    );

    final sdkLayout = sdkConfigurationProvider.sdkLayout;

    webRunner = ResidentWebRunner(
      mainUri: entry,
      urlTunneler: debugSettings.urlEncoder,
      projectDirectory: Directory(project.absolutePackageDirectory).uri,
      packageConfigFile: project.packageConfigFile,
      packageUriMapper: packageUriMapper,
      fileSystemRoots: [Directory(project.absolutePackageDirectory).uri],
      fileSystemScheme: 'org-dartlang-app',
      outputPath: outputDir.path,
      compilerOptions: compilerOptions,
      sdkLayout: sdkLayout,
      verbose: testSettings.verboseCompiler,
    );

    final assetServerPort = await findUnusedPort();
    final hostname = appMetadata.hostname;
    await webRunner.run(
      frontendServerFileSystem,
      hostname: hostname,
      port: assetServerPort,
      index: filePathToServe,
    );

    expressionCompiler = testSettings.enableExpressionEvaluation
        ? webRunner.expressionCompiler
        : null;

    basePath = webRunner.devFS!.assetServer.basePath;
    assetReader = webRunner.devFS!.assetServer;
    assetHandler = webRunner.devFS!.assetServer.handleRequest;
    loadStrategy = switch ((
      testSettings.moduleFormat,
      buildSettings.canaryFeatures,
    )) {
      (ModuleFormat.amd, _) => FrontendServerRequireStrategyProvider(
        testSettings.reloadConfiguration,
        assetReader,
        packageUriMapper,
        () async => {},
        buildSettings,
      ).strategy,
      (ModuleFormat.ddc, true) =>
        FrontendServerDdcLibraryBundleStrategyProvider(
          testSettings.reloadConfiguration,
          assetReader,
          packageUriMapper,
          () async => {},
          buildSettings,
          reloadedSourcesUri: reloadedSourcesUri,
        ).strategy,
      (ModuleFormat.ddc, false) => FrontendServerDdcStrategyProvider(
        testSettings.reloadConfiguration,
        assetReader,
        packageUriMapper,
        () async => {},
        buildSettings,
      ).strategy,
      _ => throw Exception(
        'Unsupported DDC module format '
        '${testSettings.moduleFormat.name}.',
      ),
    };
    buildResults = const Stream<dwds.BuildResult>.empty();
  }
}
