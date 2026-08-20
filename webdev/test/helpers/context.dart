// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
import 'package:dwds/src/services/daemon_expression_compiler.dart';
import 'package:dwds/src/services/expression_compiler_service.dart';
import 'package:dwds/src/utilities/web_path_translator.dart';
import 'package:dwds_test_common/fixtures/context.dart';
import 'package:dwds_test_common/fixtures/utilities.dart';
import 'package:dwds_test_common/frontend_server_common/devfs.dart';
import 'package:dwds_test_common/utilities.dart';
import 'package:file/local.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
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

mixin BuildDaemonContextMixin on TestContext {
  BuildDaemonClient get daemonClient;

  @override
  Future<void> waitForSuccessfulBuild({
    Duration? timeout,
    bool propagateToBrowser = false,
    bool allowFailure = false,
  }) async {
    final buildStartCompleter = Completer<void>();
    final buildSuccessCompleter = Completer<void>();
    final subscription = daemonClient.buildResults.listen((results) {
      final isStartedEvent = results.results.any(
        (r) => r.status == daemon.BuildStatus.started,
      );
      final isSucceededEvent = results.results.any(
        (r) => r.status == daemon.BuildStatus.succeeded,
      );
      final isFailedEvent = results.results.any(
        (r) => r.status == daemon.BuildStatus.failed,
      );

      if (isStartedEvent) {
        if (!buildStartCompleter.isCompleted) buildStartCompleter.complete();
      }
      if (isFailedEvent) {
        if (!buildSuccessCompleter.isCompleted) {
          final failedResult = results.results.firstWhere(
            (r) => r.status == daemon.BuildStatus.failed,
          );
          final daemonError =
              failedResult.error ?? 'Unknown daemon compilation error';
          if (allowFailure) {
            buildSuccessCompleter.complete();
          } else {
            buildSuccessCompleter.completeError(
              StateError('Build daemon build failed.\nError: $daemonError'),
            );
          }
        }
      }
      if (buildStartCompleter.isCompleted && isSucceededEvent) {
        if (!buildSuccessCompleter.isCompleted) {
          buildSuccessCompleter.complete();
        }
      }
    });

    var isWaitingForSuccess = false;
    try {
      var timedOutWaitingForStart = false;
      await buildStartCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          timedOutWaitingForStart = true;
        },
      );

      if (timedOutWaitingForStart) {
        return;
      }

      isWaitingForSuccess = true;
      await buildSuccessCompleter.future.timeout(
        timeout ?? const Duration(seconds: 60),
      );
    } catch (e) {
      if (e is TimeoutException) {
        // Return if an edit did not trigger a rebuild/recompile.
        if (!isWaitingForSuccess) {
          return;
        }
        // If the build started but never finished, the test has likely hung.
        rethrow;
      }
      rethrow;
    } finally {
      await subscription.cancel();
    }

    if (propagateToBrowser) {
      final delay = Platform.isWindows
          ? const Duration(seconds: 5)
          : const Duration(seconds: 2);
      await Future<void>.delayed(delay);
    }
  }
}

class BuildDaemonTestContext extends TestContext with BuildDaemonContextMixin {
  final _logger = logging.Logger('BuildDaemonTestContext');
  BuildDaemonTestContext(super.project, super.sdkConfigurationProvider)
    : super.protected();

  late AssetReader _assetReader;
  late Handler _assetHandler;
  late LoadStrategy _loadStrategy;
  late Stream<dwds.BuildResult> _buildResults;
  ExpressionCompiler? _expressionCompiler;

  @override
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
      useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
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
      '--build-filter=${project.directoryToServe}/**',
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
      DefaultBuildTarget(
        (b) => b
          ..target = project.webAssetsPath
          ..reportChangedAssets = true,
      ),
    );
    daemonClient.startBuild();

    await waitForSuccessfulBuild();

    final assetServerPort = daemonPort(project.absolutePackageDirectory);
    _assetHandler = switch ((
      testSettings.moduleFormat,
      buildSettings.canaryFeatures,
    )) {
      (ModuleFormat.ddc, true) =>
        _createBuildRunnerDdcLibraryBundleAssetHandler(this, assetServerPort),
      _ => createBuildRunnerProxyHandler(
        directoryToServe: project.directoryToServe,
        client: client,
        assetServerPort: assetServerPort,
      ),
    };
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
    } else {
      _expressionCompiler = null;
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
        (result) => result.target == project.webAssetsPath,
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
    ddcService = null;
    _expressionCompiler = null;
    try {
      await daemonClient.close();
    } catch (_) {}
  }
}

class BuildDaemonAndFrontendServerTestContext extends TestContext
    with BuildDaemonContextMixin {
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

  @override
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

  /// Forwards expression compilation requests to the persistent Frontend Server
  /// process via socket.
  Future<Map<String, dynamic>> _compileExpressionWithDaemon(
    Map<String, dynamic> request,
  ) async {
    final file = _fesManagerConfigFile(this);
    if (!await file.exists()) {
      throw StateError('FES port not found in ${file.path}');
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map;
    final port = json['port'] as int?;
    if (port == null) {
      throw StateError('FES port not found in ${file.path}');
    }

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    try {
      socket.writeln(jsonEncode(request));
      final responseStr = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first;
      return jsonDecode(responseStr) as Map<String, dynamic>;
    } finally {
      await socket.close();
    }
  }

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
      useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
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
      '--build-filter=${project.directoryToServe}/**',
    ];

    if (testSettings.enableExpressionEvaluation) {
      _logger.info('Starting Frontend Server Manager');
      final sdkDir = p.dirname(p.dirname(sdkLayout.dartPath));
      final testScratchSpaceDir = Directory(
        p.join(
          project.absolutePackageDirectory,
          '.dart_tool',
          'test_scratch_space',
        ),
      );
      if (testScratchSpaceDir.existsSync()) {
        testScratchSpaceDir.deleteSync(recursive: true);
      }
      testScratchSpaceDir.createSync(recursive: true);

      final sourcePackagesFile = File(
        p.join(
          project.absolutePackageDirectory,
          '.dart_tool',
          'package_config.json',
        ),
      );
      final packagesFile = File(
        p.join(testScratchSpaceDir.path, '.dart_tool', 'package_config.json'),
      );
      packagesFile.parent.createSync(recursive: true);

      final originalJson =
          jsonDecode(sourcePackagesFile.readAsStringSync())
              as Map<String, dynamic>;
      final packagesList = originalJson['packages'] as List<dynamic>;
      for (final package in packagesList) {
        final packageMap = package as Map<String, dynamic>;
        var rootUri = Uri.parse(packageMap['rootUri'] as String);
        if (!rootUri.isAbsolute) {
          rootUri = sourcePackagesFile.parent.uri.resolveUri(rootUri);
        }
        packageMap['rootUri'] = rootUri.toString();
      }
      packagesFile.writeAsStringSync(jsonEncode(originalJson));

      options.addAll([
        '--define',
        'build_web_compilers|ddc=scratch-space-dir='
            '${testScratchSpaceDir.path}',
      ]);
      final fesSnapshot = p.join(
        project.absolutePackageDirectory,
        '.dart_tool',
        'fes_manager.snapshot',
      );

      final buildWebCompilers =
          packagesList.firstWhere(
                (pkg) => (pkg as Map)['name'] == 'build_web_compilers',
                orElse: () => null,
              )
              as Map<String, dynamic>?;

      String fesManagerPath;
      String fesManagerPackagesFile;

      if (buildWebCompilers != null) {
        final pkgRootUri = Uri.parse(buildWebCompilers['rootUri'] as String);
        final pkgRootPath =
            sourcePackagesFile.parent.uri.resolveUri(pkgRootUri).toFilePath();
        fesManagerPath = p.join(pkgRootPath, 'bin', 'fes_manager.dart');
        fesManagerPackagesFile = sourcePackagesFile.path;
      } else {
        final resolvedUri = Isolate.resolvePackageUriSync(
          Uri.parse('package:build_web_compilers/build_web_compilers.dart'),
        );
        if (resolvedUri == null) {
          throw StateError(
            'Unable to resolve package:build_web_compilers in isolate.',
          );
        }
        final pkgRootPath = p.dirname(p.dirname(resolvedUri.toFilePath()));
        fesManagerPath = p.join(pkgRootPath, 'bin', 'fes_manager.dart');
        final currentConfigUri = await Isolate.packageConfig;
        fesManagerPackagesFile =
            currentConfigUri?.toFilePath() ?? sourcePackagesFile.path;
      }

      final compileResult = await Process.run(sdkLayout.dartPath, [
        'compile',
        'kernel',
        '--packages=$fesManagerPackagesFile',
        '-o',
        fesSnapshot,
        fesManagerPath,
      ]);
      if (compileResult.exitCode != 0) {
        throw StateError(
          'Failed to compile Frontend Server Manager:\n'
          'Exit code: ${compileResult.exitCode}\n'
          'Stdout: ${compileResult.stdout}\n'
          'Stderr: ${compileResult.stderr}',
        );
      }

      final args = [
        fesSnapshot,
        sdkDir,
        p.toUri(testScratchSpaceDir.path).toString(),
        p.toUri(packagesFile.path).toString(),
      ];
      final configFile = _fesManagerConfigFile(this);
      if (configFile.existsSync()) {
        configFile.deleteSync();
      }
      fesProcess = await Process.start(
        sdkLayout.dartPath,
        args,
        workingDirectory: project.absolutePackageDirectory,
      );

      fesProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _logger.info('FES Manager STDOUT: $line');
          });
      fesProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            _logger.warning('FES Manager STDERR: $line');
          });

      while (!await configFile.exists()) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    try {
      daemonClient = await connectClient(
        sdkLayout.dartPath,
        project.absolutePackageDirectory,
        options,
        (log) {
          final record = log.toLogRecord();
          _logger.log(
            record.level,
            record.message,
            record.error,
            record.stackTrace,
          );
        },
      );
    } catch (e) {
      final daemonLogFile = File(
        p.join(
          project.absolutePackageDirectory,
          '.dart_tool',
          'build',
          'daemon',
          'log',
        ),
      );
      if (daemonLogFile.existsSync()) {
        _logger.warning(
          'Daemon startup log content:\n'
          '${daemonLogFile.readAsStringSync()}',
        );
      } else {
        _logger.warning(
          'Daemon startup log file does not exist at: '
          '${daemonLogFile.path}',
        );
      }
      rethrow;
    }
    daemonClient.registerBuildTarget(
      DefaultBuildTarget(
        (b) => b
          ..target = project.webAssetsPath
          ..outputLocation = OutputLocation(
            (o) => o
              ..output = outputDir.path
              ..useSymlinks = false
              ..hoist = true,
          ).toBuilder()
          ..reportChangedAssets = true,
      ),
    );
    final buildFuture = waitForSuccessfulBuild();
    daemonClient.startBuild();

    await buildFuture;
    final assetServerPort = daemonPort(project.absolutePackageDirectory);

    _assetHandler = _createBuildRunnerDdcLibraryBundleAssetHandler(
      this,
      assetServerPort,
    );

    _assetReader = ProxyServerAssetReader.fromHandler(_assetHandler);

    if (testSettings.enableExpressionEvaluation) {
      _expressionCompiler = DaemonExpressionCompiler(
        _compileExpressionWithDaemon,
      );
    } else {
      _expressionCompiler = null;
    }
    frontendServerFileSystem = const LocalFileSystem();
    final packageUriMapper = await BuildRunnerPathResolver.create(
      frontendServerFileSystem,
      project.packageConfigFile,
      useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
    );
    _loadStrategy = switch ((
      testSettings.moduleFormat,
      buildSettings.canaryFeatures,
      testSettings.enableExpressionEvaluation,
    )) {
      (ModuleFormat.ddc, true, true) =>
        FrontendServerBuildDaemonStrategyProvider(
          testSettings.reloadConfiguration,
          _assetReader,
          packageUriMapper,
          () async => {},
          buildSettings,
          injectScriptLoad: false,
          reloadedSourcesUri: reloadedSourcesUri,
        ).strategy,
      (ModuleFormat.ddc, true, false) =>
        BuildRunnerDdcLibraryBundleStrategyProvider(
          testSettings.reloadConfiguration,
          _assetReader,
          buildSettings,
          reloadedSourcesUri: reloadedSourcesUri,
        ).strategy,
      _ => throw Exception(
        'Unsupported DDC module format when compiling with Frontend '
        'Server + build_runner ${testSettings.moduleFormat.name}.',
      ),
    };

    // Map build results.
    _buildResults = testSettings.enableExpressionEvaluation
        ? const Stream<dwds.BuildResult>.empty()
        : daemonClient.buildResults.map((results) {
            final result = results.results.firstWhere(
              (result) => result.target == project.webAssetsPath,
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
    try {
      await daemonClient.close();
    } catch (_) {}
  }

  @override
  Future<void> waitForSuccessfulBuild({
    Duration? timeout,
    bool propagateToBrowser = false,
    bool allowFailure = false,
  }) async {
    lastBuildFailed = false;
    // Wait for the build until the timeout is reached:
    final results = await daemonClient.buildResults
        .firstWhere(
          (daemon.BuildResults results) => results.results.any(
            (daemon.BuildResult result) =>
                result.status == daemon.BuildStatus.succeeded ||
                (allowFailure && result.status == daemon.BuildStatus.failed),
          ),
        )
        .timeout(timeout ?? const Duration(seconds: 60));

    lastBuildFailed = results.results.any(
      (daemon.BuildResult result) => result.status == daemon.BuildStatus.failed,
    );

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
}

File _fesManagerConfigFile(TestContext context) => File(
  p.join(
    context.project.absolutePackageDirectory,
    '.dart_tool',
    'build',
    'fes_manager_config',
  ),
);

Handler _createBuildRunnerDdcLibraryBundleAssetHandler(
  TestContext context,
  int assetServerPort,
) {
  final rootProxy = proxyHandler(
    'http://localhost:$assetServerPort/',
    client: context.client,
  );
  final entrypointProxy = proxyHandler(
    'http://localhost:$assetServerPort/${context.project.directoryToServe}/',
    client: context.client,
  );

  return (request) async {
    final path = request.url.path;
    var newPath = path;

    // Translate FES paths to package:build paths.
    newPath = WebPathTranslator.translateFesToBuildRunnerPath(newPath);
    var requestToProxy = request;
    if (newPath != path) {
      requestToProxy = shelf.Request(
        request.method,
        request.requestedUri.replace(path: newPath),
        headers: request.headers,
        body: request.read(),
        context: request.context,
      );
    }

    // Serve reloaded_sources.json.
    if (newPath.endsWith(WebDevFS.reloadedSourcesFileName)) {
      if (context.lastBuildFailed) {
        return shelf.Response.internalServerError(
          body: 'Last build failed, no reloaded sources.',
        );
      }
      return shelf.Response.ok(jsonEncode(context.reloadedSources));
    }

    // Resolve compiled files (.js, .js.map, .metadata, .dill, .full.dill)
    // from either the test scratch space or the build cache.
    final isDill = newPath.endsWith('.dill') || newPath.endsWith('.full.dill');
    final isMetadata = newPath.endsWith('.metadata');
    final isPackage = newPath.startsWith('packages/');
    final isJsOrMap = newPath.endsWith('.js') || newPath.endsWith('.js.map');

    if (isDill || isMetadata || (isPackage && isJsOrMap)) {
      String relativePath;
      if (isPackage) {
        final parts = newPath.split('/');
        relativePath = parts.length > 2 ? parts.sublist(2).join('/') : newPath;
      } else {
        final prefix = '${context.project.directoryToServe}/';
        relativePath = newPath.startsWith(prefix)
            ? newPath.substring(prefix.length)
            : newPath;
      }

      final subDir = isPackage ? 'lib' : context.project.directoryToServe;

      final scratchFile = File(
        p.join(
          context.project.absolutePackageDirectory,
          '.dart_tool',
          'build',
          'test_scratch_space',
          subDir,
          relativePath,
        ),
      );

      final generatedFile = File(
        p.join(
          context.project.absolutePackageDirectory,
          '.dart_tool',
          'build',
          'generated',
          context.project.packageName,
          subDir,
          relativePath,
        ),
      );

      Uint8List? fileBytes;
      if (scratchFile.existsSync()) {
        fileBytes = scratchFile.readAsBytesSync();
      } else if (generatedFile.existsSync()) {
        fileBytes = generatedFile.readAsBytesSync();
      }

      if (fileBytes != null) {
        final String mimeType;
        if (newPath.endsWith('.js')) {
          mimeType = 'application/javascript';
        } else if (newPath.endsWith('.json') ||
            newPath.endsWith('.map') ||
            newPath.endsWith('.metadata')) {
          mimeType = 'application/json';
        } else {
          mimeType = 'application/octet-stream';
        }

        return shelf.Response.ok(
          fileBytes,
          headers: {
            HttpHeaders.contentTypeHeader: mimeType,
            HttpHeaders.contentLengthHeader: fileBytes.length.toString(),
          },
        );
      }
    }

    // Serve the DDC merged metadata. Merging is done by the FES manager.
    if (newPath.endsWith('.ddc_merged_metadata')) {
      String? mergedContent;
      final configFile = _fesManagerConfigFile(context);
      if (await configFile.exists()) {
        try {
          final configJson = jsonDecode(await configFile.readAsString()) as Map;
          final port = configJson['port'] as int?;
          if (port != null) {
            final socket = await Socket.connect(
              InternetAddress.loopbackIPv4,
              port,
            );
            try {
              socket.writeln(jsonEncode({'instruction': 'MERGE_ALL_METADATA'}));
              final responseStr = await socket
                  .cast<List<int>>()
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .first;
              final response = jsonDecode(responseStr) as Map;
              mergedContent = response['content'] as String?;
            } finally {
              await socket.close();
            }
          }
        } catch (_) {
          // Ignore socket or parsing errors, letting the request fail
          // gracefully or fall through.
        }
      }

      if (mergedContent != null) {
        final bytes = Uint8List.fromList(utf8.encode(mergedContent));
        return shelf.Response.ok(
          bytes,
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
            HttpHeaders.contentLengthHeader: bytes.length.toString(),
          },
        );
      }
    }

    // Swap between [rootProxy] and [entrypointProxy] to handle path serving
    // differences for entrypoints vs library files.
    //
    // Use [rootProxy] for paths that already include the directory to serve
    // (e.g., 'web/main.dart', 'packages/...', 'example/...').
    //
    // Use [entrypointProxy] for files requested at the root (e.g. 'main.dart'
    // or 'index.html'), These implicitly prepend [directoryToServe].
    final prefix = '${context.project.directoryToServe}/';
    var requestToProxyFinal = requestToProxy;
    if (newPath.startsWith(prefix)) {
      requestToProxyFinal = requestToProxy.change(
        path: context.project.directoryToServe,
      );
    }

    final response =
        await (newPath.startsWith(prefix) ||
                newPath.startsWith('packages/') ||
                newPath.startsWith('example/')
            ? rootProxy(requestToProxyFinal)
            : entrypointProxy(requestToProxyFinal));
    return response;
  };
}

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
      .listen(stderrBuffer.add);

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
    'Command: $dartPath run build_runner daemon ${options.join(' ')}',
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
