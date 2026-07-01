// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @skip_package_deps_validation

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:dwds/asset_reader.dart';
import 'package:dwds/dart_web_debug_service.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/loaders/build_runner_strategy_provider.dart';
import 'package:dwds/src/loaders/frontend_server_strategy_provider.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/readers/proxy_server_asset_reader.dart';
import 'package:dwds/src/services/chrome/chrome_proxy_service.dart';
import 'package:dwds/src/services/daemon_expression_compiler.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/services/expression_compiler_service.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/ddc_uri_translator.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:dwds_test_common/logging.dart';
import 'package:dwds_test_common/test_sdk_configuration.dart';
import 'package:dwds_test_common/utilities.dart';
import 'package:file/local.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:webdriver/async_io.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../frontend_server_common/devfs.dart';
import '../../frontend_server_common/resident_runner.dart';
import 'project.dart';
import 'server.dart';
import 'utilities.dart';

final _exeExt = Platform.isWindows ? '.exe' : '';

const isRPCError = TypeMatcher<RPCError>();
const isSentinelException = TypeMatcher<SentinelException>();

final Matcher throwsRPCError = throwsA(isRPCError);
final Matcher throwsSentinelException = throwsA(isSentinelException);

Matcher isRPCErrorWithMessage(String message) => isA<RPCError>().having(
  (RPCError e) => e.message,
  'message',
  contains(message),
);
Matcher throwsRPCErrorWithMessage(String message) =>
    throwsA(isRPCErrorWithMessage(message));

Matcher isRPCErrorWithCode(int code) =>
    isA<RPCError>().having((RPCError e) => e.code, 'code', equals(code));
Matcher throwsRPCErrorWithCode(int code) => throwsA(isRPCErrorWithCode(code));

enum CompilationMode {
  buildDaemon(false, true, false),
  frontendServer(true, false, false),
  buildDaemonAndFrontendServer(true, true, true);

  final bool usesFrontendServer;
  final bool usesBuildDaemon;
  final bool usesDdcModulesOnly;

  const CompilationMode(
    this.usesFrontendServer,
    this.usesBuildDaemon,
    this.usesDdcModulesOnly,
  );
}

class TestContext {
  final TestProject project;
  final TestSdkConfigurationProvider sdkConfigurationProvider;

  String get appUrl => _appUrl!;
  late String? _appUrl;

  WipConnection get tabConnection => _tabConnection!;
  late WipConnection? _tabConnection;

  TestServer get testServer => _testServer!;
  TestServer? _testServer;

  Dwds? get dwds => _testServer?.dwds;

  BuildDaemonClient get daemonClient => _daemonClient!;
  BuildDaemonClient? _daemonClient;

  ResidentWebRunner get webRunner => _webRunner!;
  ResidentWebRunner? _webRunner;

  WebDriver get webDriver => _webDriver!;
  WebDriver? _webDriver;

  Process get chromeDriver => _chromeDriver!;
  Process? _chromeDriver;
  Process? _fesProcess;
  bool _lastBuildFailed = false;

  WebkitDebugger get webkitDebugger => _webkitDebugger!;
  late WebkitDebugger? _webkitDebugger;

  Handler get assetHandler => _assetHandler!;
  late Handler? _assetHandler;

  Client get client => _client!;
  Client? _client;

  ExpressionCompilerService? ddcService;

  int get port => _port!;
  late int? _port;

  Directory get outputDir => _outputDir!;
  Directory? _outputDir;

  late WipConnection extensionConnection;
  late AppConnection appConnection;
  late DebugConnection debugConnection;

  final _logger = logging.Logger('Context');

  final _serviceNameToMethod = <String, String?>{};

  late LocalFileSystem frontendServerFileSystem;

  late String _hostname;
  late TestSettings _testSettings;

  /// Internal VM service.
  ///
  /// Prefer using [vmService] instead in tests when possible, to include
  /// testing of the VmServerConnection (bypassed when using [service]).
  ChromeProxyService get service => fetchChromeProxyService(debugConnection);

  /// External VM service.
  VmService get vmService => debugConnection.vmService;

  TestContext(this.project, this.sdkConfigurationProvider);

  Future<void> setUp({
    TestSettings testSettings = const TestSettings(),
    TestAppMetadata appMetadata = const TestAppMetadata.externalApp(),
    TestDebugSettings debugSettings =
        const TestDebugSettings.noDevToolsLaunch(),
  }) async {
    _testSettings = testSettings;
    _reloadedSources.clear();
    try {
      // Build settings to return from load strategy.
      final buildSettings = TestBuildSettings(
        appEntrypoint: project.dartEntryFilePackageUri,
        canaryFeatures: testSettings.canaryFeatures,
        isFlutterApp: testSettings.isFlutterApp,
        experiments: testSettings.experiments,
        useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
      );

      // Make sure configuration was created correctly.
      final sdkLayout = sdkConfigurationProvider.sdkLayout;
      final configuration = await sdkConfigurationProvider.configuration;
      configuration.validate();
      await project.setUp();

      DartUri.currentDirectory = project.absolutePackageDirectory;

      _logger.info(
        'Serving: ${project.directoryToServe}/${project.filePathToServe}',
      );
      _logger.info('Project: ${project.absolutePackageDirectory}');
      _logger.info('Packages: ${project.packageConfigFile}');
      _logger.info('Entry: ${project.dartEntryFilePath}');

      setCurrentLogWriter(debug: true);

      _client = IOClient(
        HttpClient()
          ..maxConnectionsPerHost = 200
          ..idleTimeout = const Duration(seconds: 30)
          ..connectionTimeout = const Duration(seconds: 30),
      );

      final systemTempDir = Directory.systemTemp;
      _outputDir = systemTempDir.createTempSync('foo bar');

      final chromeDriverPort = await findUnusedPort();
      final chromeDriverUrlBase = 'wd/hub';
      try {
        _chromeDriver = await Process.start('chromedriver$_exeExt', [
          '--port=$chromeDriverPort',
          '--url-base=$chromeDriverUrlBase',
        ]);
        final stdOutLines = chromeDriver.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();

        final stdErrLines = chromeDriver.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();

        // Sometimes ChromeDriver can be slow to startup.
        // This was seen on a github actions run:
        // > 11:22:59.924700: ChromeDriver stdout: Starting ChromeDriver
        // >                  139.0.7258.154 ([...]) on port 38107
        // > [...]
        // > 11:23:00.237350: ChromeDriver stdout: ChromeDriver was started
        // >                  successfully on port 38107.
        // Where in the 300+ ms it took before it was actually ready to accept
        // a connection we had tried - and failed - to connect.
        // We therefore wait until ChromeDriver reports that it has started
        // successfully.

        final chromeDriverStartup = Completer<void>();
        stdOutLines.listen((line) {
          if (!chromeDriverStartup.isCompleted &&
              line.contains('was started successfully')) {
            chromeDriverStartup.complete();
          }
          _logger.finest('ChromeDriver stdout: $line');
        });
        stdErrLines.listen(
          (line) => _logger.warning('ChromeDriver stderr: $line'),
        );

        await chromeDriverStartup.future;
      } catch (e) {
        throw StateError(
          'Could not start ChromeDriver. Is it installed?\nError: $e',
        );
      }

      final pubUpgradeResult = await Process.run(sdkLayout.dartPath, [
        'pub',
        'upgrade',
      ], workingDirectory: project.absolutePackageDirectory);
      if (pubUpgradeResult.exitCode != 0) {
        _logger.severe(
          '"dart pub upgrade" failed in ${project.absolutePackageDirectory}:',
        );
        _logger.severe(pubUpgradeResult.stdout);
        _logger.severe(pubUpgradeResult.stderr);
      }

      ExpressionCompiler? expressionCompiler;
      AssetReader assetReader;
      Stream<BuildResults> buildResults;
      LoadStrategy loadStrategy;
      var basePath = '';
      var filePathToServe = project.filePathToServe;

      // Start the HTTP server and save its used port.
      final httpServer = await startHttpServer('localhost');
      _port = httpServer.port;

      final reloadedSourcesUri = Uri.parse(
        'http://localhost:$_port/${WebDevFS.reloadedSourcesFileName}',
      );

      switch (testSettings.compilationMode) {
        case CompilationMode.buildDaemon:
          {
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
            _daemonClient = await connectClient(
              sdkLayout.dartPath,
              project.absolutePackageDirectory,
              options,
              (log) {
                final record = log.toLogRecord();
                final name = record.loggerName == ''
                    ? ''
                    : '${record.loggerName}: ';
                print('${record.level.name}: $name${record.message}');
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

            final assetServerPort = daemonPort(
              project.absolutePackageDirectory,
            );
            _assetHandler = _createBuildRunnerProxyHandler(assetServerPort);
            if (testSettings.moduleFormat == ModuleFormat.ddc &&
                buildSettings.canaryFeatures) {
              _assetHandler = _createBuildRunnerDdcLibraryBundleAssetHandler(
                assetServerPort,
              );
            } else {
              _assetHandler = _createBuildRunnerProxyHandler(assetServerPort);
            }
            assetReader = ProxyServerAssetReader(
              assetServerPort,
              root: project.directoryToServe,
            );

            if (testSettings.enableExpressionEvaluation) {
              ddcService = ExpressionCompilerService(
                'localhost',
                _port!,
                verbose: testSettings.verboseCompiler,
                sdkConfigurationProvider: sdkConfigurationProvider,
              );
              expressionCompiler = ddcService;
            }

            loadStrategy = switch ((
              testSettings.moduleFormat,
              buildSettings.canaryFeatures,
            )) {
              (ModuleFormat.ddc, true) =>
                BuildRunnerDdcLibraryBundleStrategyProvider(
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

            buildResults = daemonClient.buildResults;
          }
          break;
        case CompilationMode.frontendServer:
          {
            filePathToServe = webCompatiblePath([
              project.directoryToServe,
              project.filePathToServe,
            ]);

            _logger.info('Serving: $filePathToServe');

            final entry = p.toUri(
              p.join(project.webAssetsPath, project.dartEntryFileName),
            );
            frontendServerFileSystem = const LocalFileSystem();
            final packageUriMapper = await PackageUriMapper.create(
              frontendServerFileSystem,
              project.packageConfigFile,
              useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
            );

            final compilerOptions = TestCompilerOptions(
              experiments: buildSettings.experiments,
              canaryFeatures: buildSettings.canaryFeatures,
              moduleFormat: testSettings.moduleFormat,
            );

            _webRunner = ResidentWebRunner(
              mainUri: entry,
              urlTunneler: debugSettings.urlEncoder,
              projectDirectory: Directory(project.absolutePackageDirectory).uri,
              packageConfigFile: project.packageConfigFile,
              packageUriMapper: packageUriMapper,
              fileSystemRoots: [
                Directory(project.absolutePackageDirectory).uri,
              ],
              fileSystemScheme: 'org-dartlang-app',
              outputPath: outputDir.path,
              compilerOptions: compilerOptions,
              sdkLayout: sdkLayout,
              verbose: testSettings.verboseCompiler,
            );

            final assetServerPort = await findUnusedPort();
            _hostname = appMetadata.hostname;
            await webRunner.run(
              frontendServerFileSystem,
              hostname: _hostname,
              port: assetServerPort,
              index: filePathToServe,
            );

            if (testSettings.enableExpressionEvaluation) {
              expressionCompiler = webRunner.expressionCompiler;
            }

            basePath = webRunner.devFS!.assetServer.basePath;
            assetReader = webRunner.devFS!.assetServer;
            _assetHandler = webRunner.devFS!.assetServer.handleRequest;
            loadStrategy = switch ((
              testSettings.moduleFormat,
              buildSettings.canaryFeatures,
            )) {
              (ModuleFormat.amd, _) => FrontendServerRequireStrategyProvider(
                testSettings.reloadConfiguration,
                assetReader,
                () async => {},
                buildSettings,
              ).strategy,
              (ModuleFormat.ddc, true) =>
                FrontendServerDdcLibraryBundleStrategyProvider(
                  testSettings.reloadConfiguration,
                  assetReader,
                  () async => {},
                  buildSettings,
                  reloadedSourcesUri: reloadedSourcesUri,
                ).strategy,
              (ModuleFormat.ddc, false) => FrontendServerDdcStrategyProvider(
                testSettings.reloadConfiguration,
                assetReader,
                () async => {},
                buildSettings,
              ).strategy,
              _ => throw Exception(
                'Unsupported DDC module format '
                '${testSettings.moduleFormat.name}.',
              ),
            };
            buildResults = const Stream<BuildResults>.empty();
          }
          break;
        case CompilationMode.buildDaemonAndFrontendServer:
          {
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
              final buildDir = Directory(
                p.join(project.absolutePackageDirectory, '.dart_tool', 'build'),
              );
              if (buildDir.existsSync()) {
                buildDir.deleteSync(recursive: true);
              }
              final testScratchSpaceDir = Directory(
                p.join(
                  project.absolutePackageDirectory,
                  '.dart_tool',
                  'build',
                  'test_scratch_space',
                ),
              );
              testScratchSpaceDir.createSync(recursive: true);

              // Build daemon requires a package config inside its scratch
              // space directory to resolve package paths during compilation.
              // We read the original package config from [sourcePackagesFile],
              // make all relative package paths absolute, then write the
              // resolved config to [packagesFile] inside [testScratchSpaceDir].
              final sourcePackagesFile = File(
                p.join(
                  project.absolutePackageDirectory,
                  '.dart_tool',
                  'package_config.json',
                ),
              );
              final packagesFile = File(
                p.join(
                  testScratchSpaceDir.path,
                  '.dart_tool',
                  'package_config.json',
                ),
              );
              packagesFile.parent.createSync(recursive: true);

              // Make all relative rootUris absolute based on the original packagesFile location
              // so they don't break when the file is moved to the test scratch space.
              final originalJson = jsonDecode(
                sourcePackagesFile.readAsStringSync(),
              ) as Map<String, dynamic>;
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

              options.add(
                '--define=build_web_compilers:ddc=scratch-space-dir='
                '${testScratchSpaceDir.path}',
              );
              final fesSnapshot = p.join(
                project.absolutePackageDirectory,
                '.dart_tool',
                'fes_manager.snapshot',
              );
              // Resolve the path to `fes_manager.dart`.
              // Consult the test project's package config to resolve
              // build_web_compilers, but fall back to a checkout of
              // package:build.
              final buildWebCompilers = packagesList.firstWhere(
                (pkg) => (pkg as Map)['name'] == 'build_web_compilers',
                orElse: () => null,
              ) as Map<String, dynamic>?;
              String fesManagerPath;
              if (buildWebCompilers != null) {
                final pkgRootUri = Uri.parse(
                  buildWebCompilers['rootUri'] as String,
                );
                fesManagerPath = p.join(
                  pkgRootUri.toFilePath(),
                  'bin',
                  'fes_manager.dart',
                );
              } else {
                final localBuildRepoDir = p.join(
                  p.dirname(projectRootDir),
                  'build',
                );
                fesManagerPath = p.join(
                  localBuildRepoDir,
                  'builder_pkgs',
                  'build_web_compilers',
                  'bin',
                  'fes_manager.dart',
                );
              }
              final compileResult = await Process.run(sdkLayout.dartPath, [
                'compile',
                'kernel',
                '--packages=${sourcePackagesFile.path}',
                '-o',
                fesSnapshot,
                fesManagerPath,
              ]);
              if (compileResult.exitCode != 0) {
                _logger.severe(
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
              _fesProcess = await Process.start(
                sdkLayout.dartPath,
                args,
                workingDirectory: project.absolutePackageDirectory,
              );

              final debugLog = File('/tmp/fes_manager_debug.log');
              if (debugLog.existsSync()) debugLog.deleteSync();
              _fesProcess!.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .listen((line) {
                    debugLog.writeAsStringSync(
                      'STDOUT: $line\n',
                      mode: FileMode.append,
                    );
                  });
              _fesProcess!.stderr
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .listen((line) {
                    debugLog.writeAsStringSync(
                      'STDERR: $line\n',
                      mode: FileMode.append,
                    );
                  });

              final configFile = File(
                p.join(
                  project.absolutePackageDirectory,
                  '.dart_tool',
                  'build',
                  'fes_manager_config',
                ),
              );
              // Wait for `fes_manager` to create the config file.
              while (!await configFile.exists()) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }

            try {
              _daemonClient = await connectClient(
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
                  'Daemon startup log content:\n${daemonLogFile.readAsStringSync()}',
                );
              } else {
                _logger.warning(
                  'Daemon startup log file does not exist at: ${daemonLogFile.path}',
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
                      ..useSymlinks = true
                      ..hoist = true,
                  ).toBuilder()
                  ..reportChangedAssets = true,
              ),
            );
            final buildFuture = waitForSuccessfulBuild(cleanStart: true);
            daemonClient.startBuild();

            await buildFuture;

            final assetServerPort = daemonPort(
              project.absolutePackageDirectory,
            );
            _assetHandler = _createBuildRunnerProxyHandler(assetServerPort);
            if (testSettings.moduleFormat == ModuleFormat.ddc &&
                buildSettings.canaryFeatures) {
              _assetHandler = _createBuildRunnerDdcLibraryBundleAssetHandler(
                assetServerPort,
              );
            } else {
              _assetHandler = _createBuildRunnerProxyHandler(assetServerPort);
            }
            assetReader = ProxyServerAssetReader.fromHandler(_assetHandler!);

            if (testSettings.enableExpressionEvaluation) {
              expressionCompiler = DaemonExpressionCompiler((request) async {
                final file = File(
                  p.join(
                    project.absolutePackageDirectory,
                    '.dart_tool',
                    'build',
                    'fes_manager_config',
                  ),
                );
                if (await file.exists()) {
                  final content = await file.readAsString();
                  int? port;
                  final json = jsonDecode(content) as Map;
                  port = json['port'] as int?;
                  if (port != null) {
                    final socket = await Socket.connect(
                      InternetAddress.loopbackIPv4,
                      port,
                    );
                    try {
                      socket.writeln(jsonEncode(request));
                      final responseStr = await socket
                          .cast<List<int>>()
                          .transform(utf8.decoder)
                          .transform(const LineSplitter())
                          .first;
                      final compileResult = jsonDecode(responseStr);

                      if (compileResult is Map) {
                        if (compileResult.containsKey('error')) {
                          return {
                            'result': compileResult['error'] as String,
                            'isError': true,
                          };
                        }
                        final errorCount = compileResult['errorCount'] as int?;
                        final expressionData =
                            compileResult['expressionData'] as String?;

                        if (errorCount != null && errorCount > 0) {
                          return {
                            'result':
                                compileResult['errorMessage'] as String? ??
                                'Unknown error',
                            'isError': true,
                          };
                        }

                        if (expressionData != null) {
                          final decodedResult = utf8.decode(
                            base64.decode(expressionData),
                          );
                          return {'result': decodedResult, 'isError': false};
                        }
                      }

                      return {
                        'result': 'Failed to read evaluation result',
                        'isError': true,
                      };
                    } finally {
                      await socket.close();
                    }
                  }
                }
                throw StateError(
                  'FES port not found in .dart_tool/build/fes_manager_config',
                );
              });
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
              testSettings.enableExpressionEvaluation,
            )) {
              (ModuleFormat.ddc, true, true) =>
                FrontendServerBuildDaemonStrategyProvider(
                  testSettings.reloadConfiguration,
                  assetReader,
                  () async => {},
                  buildSettings,
                  injectScriptLoad: false,
                  reloadedSourcesUri: reloadedSourcesUri,
                ).strategy,
              (ModuleFormat.ddc, true, false) =>
                BuildRunnerDdcLibraryBundleStrategyProvider(
                  testSettings.reloadConfiguration,
                  assetReader,
                  buildSettings,
                  reloadedSourcesUri: reloadedSourcesUri,
                ).strategy,
              _ => throw Exception(
                'Unsupported DDC module format when compiling with Frontend '
                'Server + build_runner ${testSettings.moduleFormat.name}.',
              ),
            };
            // If expression evaluation is disabled, the build daemon is
            // responsible for triggering hot reloads/restarts via its
            // buildResults stream. We must listen to it to prevent browser
            // reload events from hanging.
            buildResults = testSettings.enableExpressionEvaluation
                ? const Stream<BuildResults>.empty()
                : daemonClient.buildResults;
          }
          break;
      }

      final debugPort = await findUnusedPort();
      if (testSettings.launchChrome) {
        // If the environment variable DWDS_DEBUG_CHROME is set to the string
        // true then Chrome will be launched with a UI rather than headless.
        // If the extension is enabled, then Chrome will be launched with a UI
        // since headless Chrome does not support extensions.
        final enableDebugExtension = debugSettings.enableDebugExtension;
        final headless =
            Platform.environment['DWDS_DEBUG_CHROME'] != 'true' &&
            !enableDebugExtension;
        if (enableDebugExtension) {
          await _buildDebugExtension();
        }
        final capabilities = Capabilities.chrome
          ..addAll({
            Capabilities.chromeOptions: {
              'args': [
                // --disable-gpu speeds up the tests that use ChromeDriver when
                // they are run on GitHub Actions.
                '--disable-gpu',
                'remote-debugging-port=$debugPort',
                if (enableDebugExtension)
                  '--load-extension=debug_extension/prod_build',
                if (headless) '--headless',
              ],
            },
          });
        _webDriver = await createDriver(
          spec: WebDriverSpec.JsonWire,
          desired: capabilities,
          uri: Uri.parse(
            'http://127.0.0.1:$chromeDriverPort/$chromeDriverUrlBase/',
          ),
        );
      }

      // The debugger tab must be enabled and connected before certain
      // listeners in DWDS or `main` is run.
      final tabConnectionCompleter = Completer<void>();
      final appConnectionCompleter = Completer<void>();
      final connection = ChromeConnection('localhost', debugPort);

      // TODO(srujzs): In the case of the frontend server, it doesn't make sense
      // that we initialize a new HTTP server instead of reusing the one in
      // `TestAssetServer`. We should instead use that one to align with Flutter
      // tools.
      _testServer = await TestServer.start(
        debugSettings: debugSettings.copyWith(
          expressionCompiler: expressionCompiler,
        ),
        appMetadata: appMetadata,
        port: port,
        assetHandler: assetHandler,
        assetReader: assetReader,
        strategy: loadStrategy,
        // Build daemon serves assets relative to the web root (e.g. 'web/'),
        // but standalone FES serves assets relative to the target directory.
        target: testSettings.compilationMode.usesBuildDaemon
            ? project.webAssetsPath
            : project.directoryToServe,
        buildResults: buildResults,
        chromeConnection: () async => connection,
        httpServer: httpServer,
      );

      _testServer!.dwds.connectedApps.listen((connection) async {
        // Ensure that we've established a tab connection before running main.
        await tabConnectionCompleter.future;
        if (testSettings.autoRun) {
          connection.runMain();
        }

        // We may reuse the app connection, so only save it the first time
        // it's encountered.
        if (!appConnectionCompleter.isCompleted) {
          appConnection = connection;
          appConnectionCompleter.complete();
        }
      });

      _appUrl = basePath.isEmpty
          ? 'http://localhost:$port/$filePathToServe'
          : 'http://localhost:$port/$basePath/$filePathToServe';

      if (testSettings.launchChrome) {
        await _webDriver?.get(appUrl);
        final tab = await connection.getTab((t) => t.url == appUrl);
        if (tab != null) {
          _tabConnection = await tab.connect();
          await tabConnection.runtime.enable();
          await tabConnection.debugger.enable().then(
            (_) => tabConnectionCompleter.complete(),
          );
        } else {
          throw StateError('Unable to connect to tab.');
        }

        if (debugSettings.enableDebugExtension) {
          final extensionTab = await _fetchDartDebugExtensionTab(connection);
          extensionConnection = await extensionTab.connect();
          await extensionConnection.runtime.enable();
        }

        await appConnectionCompleter.future;
        if (debugSettings.enableDebugging && !testSettings.waitToDebug) {
          await startDebugging();
        }
        _webkitDebugger = WebkitDebugger(WipDebugger(tabConnection));
      } else {
        // No tab needs to be discovered, so fulfill the relevant completer.
        tabConnectionCompleter.complete();
      }
    } catch (e, s) {
      _logger.severe('Failed to setup the service, $e:$s');
      await tearDown();
      rethrow;
    }
  }

  /// Creates a VM service connection connected to the debug URI.
  ///
  /// This can be used to test behavior that should be available to a client
  /// connected to DWDS.
  Future<VmService> connectFakeClient() async {
    final fakeClient = await vmServiceConnectUri(debugConnection.uri);

    fakeClient.onEvent(EventStreams.kService).listen(_handleServiceEvent);
    await fakeClient.streamListen(EventStreams.kService);

    return fakeClient;
  }

  /// Returns the service extension method given the [extensionName].
  ///
  /// The extension be called by a client created with [connectFakeClient].
  String? getRegisteredServiceExtension(String extensionName) {
    if (_serviceNameToMethod.isEmpty) {
      throw StateError('''
        No registered service extensions. Did you call connectFakeClient?
      ''');
    }

    return _serviceNameToMethod[extensionName];
  }

  void _handleServiceEvent(Event e) {
    if (e.kind == EventKind.kServiceRegistered) {
      final serviceName = e.service!;
      _serviceNameToMethod[serviceName] = e.method;
    }
  }

  Future<void> startDebugging() async {
    debugConnection = await testServer.dwds.debugConnection(appConnection);
  }

  Future<void> tearDown() async {
    try {
      await _webRunner?.stop().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await _webDriver
          ?.quit(closeSession: true)
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    _chromeDriver?.kill();
    DartUri.currentDirectory = p.current;
    try {
      await _daemonClient?.close().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await ddcService?.stop().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await _testServer?.stop().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      _client?.close();
    } catch (_) {}
    try {
      _fesProcess?.kill();
    } catch (_) {}
    final dir = _outputDir;
    if (dir != null && dir.existsSync()) {
      unawaited(dir.delete(recursive: true));
    }

    // Wait for the build daemon process to fully exit before starting the next
    // test case.
    if (_testSettings.compilationMode.usesBuildDaemon) {
      final targetPath = project.absolutePackageDirectory;
      final retries = 50;
      for (var i = 0; i < retries; i++) {
        final result = Process.runSync('ps', ['aux']);
        final lines = result.stdout.toString().split('\n');
        final isStillRunning = lines.any(
          (line) =>
              line.contains('build.dart.aot') && line.contains(targetPath),
        );
        if (!isStillRunning) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    stopLogWriter();
    await project.tearDown();

    // clear the state for next setup
    _webDriver = null;
    _chromeDriver = null;
    _daemonClient = null;
    ddcService = null;
    _webRunner = null;
    _testServer = null;
    _client = null;
    _outputDir = null;
  }

  /// Given a list of edits, use file IO to write them to the file system.
  ///
  /// If `file` has the same name as the project's entry file name, that file
  /// will be edited. Otherwise, it's assumed to be a library file.
  // TODO(srujzs): It's possible we may want a library file with the same name
  // as the entry file, but this function doesn't allow that. Potentially
  // support that.
  Future<void> makeEdits(List<Edit> edits) async {
    // `dart:io`'s `stat` on Windows does not have millisecond precision so we
    // need to make sure we wait long enough that modifications result in a
    // timestamp that is guaranteed to be after the previous compile.
    // TODO(https://github.com/dart-lang/sdk/issues/51937): Remove once this bug
    // is fixed.
    _invalidatedUris.clear();
    for (var (:file, :originalString, :newString) in edits) {
      if (file == project.dartEntryFileName) {
        file = project.dartEntryFilePath;
      } else {
        file = project.dartLibFilePath(file);
      }
      final f = File(file);
      final fileContents = f.readAsStringSync();
      f.writeAsStringSync(fileContents.replaceAll(originalString, newString));

      final relativePath = p.relative(
        f.path,
        from: project.absolutePackageDirectory,
      );
      final relativeUrl = p.toUri(relativePath).path;
      if (relativeUrl.startsWith('lib/')) {
        final pathInLib = relativeUrl.substring('lib/'.length);
        _invalidatedUris.add('package:${project.packageName}/$pathInLib');
      } else if (f.path == project.dartEntryFilePath) {
        _invalidatedUris.add(project.dartEntryFilePackageUri.toString());
      }

      _updateReloadedSources(file);
    }
  }

  /// Updates the reloaded_sources.json manifest file for a running test.
  ///
  /// This logic essentially replicates the build system's naming conventions
  /// for DDC's generated code. DWDS itself uses the metadata file, but this
  /// isn't available for our test fixtures.
  /// Rules:
  /// - Entrypoints (served): web/main.dart -> main
  /// - Entrypoints (nested): test/hello_world/main.dart -> hello_world/main
  /// - Library files: lib/path/to/some_file.dart
  ///     -> packages/`package`/path/to/some_file
  void _updateReloadedSources(String absolutePath) {
    final relativePath = p.relative(
      absolutePath,
      from: project.absolutePackageDirectory,
    );
    final relativeUrl = p.toUri(relativePath).path;

    String moduleName;
    String libUri;
    String srcPath;

    if (relativeUrl.startsWith('lib/')) {
      final pathInLib = relativeUrl.substring('lib/'.length);
      final pathWithoutExtension = p.withoutExtension(pathInLib);
      final fesOnly =
          _testSettings.compilationMode.usesFrontendServer &&
          !_testSettings.compilationMode.usesBuildDaemon;
      moduleName =
          'packages/${project.packageName}/${fesOnly ? pathInLib : pathWithoutExtension}';
      libUri = 'package:${project.packageName}/$pathInLib';
      srcPath = 'packages/${project.packageName}/$pathWithoutExtension';
    } else if (absolutePath == project.dartEntryFilePath) {
      moduleName = p.withoutExtension(relativeUrl);
      libUri = project.dartEntryFilePackageUri.toString();

      final servePath = '${project.directoryToServe}/';
      if (relativeUrl.startsWith(servePath)) {
        // e.g. web/main.dart -> main
        srcPath = p.withoutExtension(relativeUrl.substring(servePath.length));
      } else {
        // e.g. example/hello_world/main.dart -> example/hello_world/main
        srcPath = moduleName;
      }
    } else {
      throw StateError(
        "Unhandled file path in test context's reloaded_sources.json: "
        " $absolutePath. Only entrypoints and files in 'lib/' are supported.",
      );
    }

    _reloadedSources.add(
      WebDevFS.createReloadedSourceEntry(
        src: '/$srcPath.ddc.js',
        module: moduleName,
        libraries: [libUri],
      ),
    );
  }

  final _reloadedSources = <Map<String, Object>>[];
  final _invalidatedUris = <String>[];

  void addLibraryFile({required String libFileName, required String contents}) {
    final file = File(project.dartLibFilePath(libFileName));
    // Library folder may not exist yet, so create it.
    file.createSync(recursive: true);
    file.writeAsStringSync(contents);
    _updateReloadedSources(file.path);
    _invalidatedUris.add('package:${project.packageName}/$libFileName');
  }

  Handler _createBuildRunnerProxyHandler(int assetServerPort) {
    return proxyHandler(
      'http://localhost:$assetServerPort/${project.directoryToServe}/',
      client: client,
    );
  }

  /// Returns a handler for build runner + the DDC Library Bundle module
  /// system.
  ///
  /// This handler intercepts specific asset requests to coordinate Frontend
  /// Server outputs with the Build Daemon asset server:
  ///
  /// 1. Remaps the FES-suffixed request path ('.dart.lib') to a Build Daemon
  ///    suffixed path ('.ddc') if necessary.
  /// 2. Serves reloaded source logs (`reloaded_sources.json`) for hot
  ///    restart/reload.
  /// 3. Resolves compiled files (.js, .js.map, .metadata, .dill) from either
  ///    the local scratch space or the build cache.
  /// 4. Proxies asset requests (entrypoints, source maps, merged metadata)
  ///    to the build daemon.
  Handler _createBuildRunnerDdcLibraryBundleAssetHandler(int assetServerPort) {
    final rootProxy = proxyHandler(
      'http://localhost:$assetServerPort/',
      client: client,
    );
    final entrypointProxy = proxyHandler(
      'http://localhost:$assetServerPort/${project.directoryToServe}/',
      client: client,
    );

    return (request) async {
      final path = request.url.path;
      var newPath = path;

      // Translate FES paths to package:build paths.
      newPath = DdcUriTranslator.translateFesToBuildRunnerPath(newPath);
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
        if (_lastBuildFailed) {
          return shelf.Response.internalServerError(
            body: 'Last build failed, no reloaded sources.',
          );
        }
        return shelf.Response.ok(jsonEncode(_reloadedSources));
      }

      // Resolve compiled files (.js, .js.map, .metadata, .dill, .full.dill)
      // from either the test scratch space or the build cache.
      final isDill =
          newPath.endsWith('.dill') || newPath.endsWith('.full.dill');
      final isMetadata = newPath.endsWith('.metadata');
      final isPackage = newPath.startsWith('packages/');
      final isJsOrMap = newPath.endsWith('.js') || newPath.endsWith('.js.map');

      if (isDill || isMetadata || (isPackage && isJsOrMap)) {
        String relativePath;
        if (isPackage) {
          final parts = newPath.split('/');
          relativePath = parts.length > 2
              ? parts.sublist(2).join('/')
              : newPath;
        } else {
          final prefix = '${project.directoryToServe}/';
          relativePath = newPath.startsWith(prefix)
              ? newPath.substring(prefix.length)
              : newPath;
        }

        final subDir = isPackage ? 'lib' : project.directoryToServe;

        final scratchFile = File(
          p.join(
            project.absolutePackageDirectory,
            '.dart_tool',
            'build',
            'test_scratch_space',
            subDir,
            relativePath,
          ),
        );

        final generatedFile = File(
          p.join(
            project.absolutePackageDirectory,
            '.dart_tool',
            'build',
            'generated',
            project.packageName,
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
        final configFile = File(
          p.join(
            project.absolutePackageDirectory,
            '.dart_tool',
            'build',
            'fes_manager_config',
          ),
        );
        if (configFile.existsSync()) {
          try {
            final configJson = jsonDecode(configFile.readAsStringSync()) as Map;
            final port = configJson['port'] as int?;
            if (port != null) {
              final socket = await Socket.connect(
                InternetAddress.loopbackIPv4,
                port,
              );
              try {
                socket.writeln(
                  jsonEncode({'instruction': 'MERGE_ALL_METADATA'}),
                );
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
      final prefix = '${project.directoryToServe}/';
      var requestToProxyFinal = requestToProxy;
      if (newPath.startsWith(prefix)) {
        requestToProxyFinal = requestToProxy.change(
          path: project.directoryToServe,
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

  Future<void> recompile({
    required bool fullRestart,
    bool allowFailure = false,
  }) async {
    final runner = _webRunner;
    if (runner != null) {
      await runner.rerun(
        fullRestart: fullRestart,
        fileServerUri: Uri.parse(
          'http://${testServer.host}:${testServer.port}',
        ),
      );
      return;
    }

    // In Build Daemon + Frontend Server mode, the Build Daemon already compiles
    // edited files automatically. We must await the successful build completion.
    if (_testSettings.compilationMode.usesBuildDaemon) {
      await waitForSuccessfulBuild(allowFailure: allowFailure);
      return;
    }
  }

  Future<void> waitForSuccessfulBuild({
    Duration? timeout,
    bool propagateToBrowser = false,
    bool cleanStart = false,
    bool allowFailure = false,
  }) async {
    // When a client connects or registers a target, build daemon broadcasts the
    // current build state over the socket. If the initial build is already done,
    // it immediately fires a cached `BuildStatus.succeeded` event.
    //
    // To ensure the test waits for a *new* compile cycle instead of instantly returning
    // on the cached event:
    // 1. Wait for `BuildStatus.started` (confirming a new build has begun)
    // 2. Wait for `BuildStatus.succeeded` (but only if we've already seen `started`)
    //
    // Unless `cleanStart` is specified - then we want to accept the cached success event.
    final started = Completer<void>();
    final succeeded = Completer<void>();
    final subscription = daemonClient.buildResults.listen((results) {
      final isStarted = results.results.any(
        (r) => r.status == BuildStatus.started,
      );
      final isSucceeded = results.results.any(
        (r) => r.status == BuildStatus.succeeded,
      );
      final isFailed = results.results.any(
        (r) => r.status == BuildStatus.failed,
      );

      if (isStarted) {
        if (!started.isCompleted) started.complete();
      }
      if (isSucceeded) {
        _lastBuildFailed = false;
      }
      if (isFailed) {
        _lastBuildFailed = true;
        if (!succeeded.isCompleted) {
          final failedResult = results.results.firstWhere(
            (r) => r.status == BuildStatus.failed,
          );
          final daemonError =
              failedResult.error ?? 'Unknown daemon compilation error';
          if (allowFailure) {
            succeeded.complete();
          } else {
            succeeded.completeError(
              StateError('Build daemon build failed.\nError: $daemonError'),
            );
          }
        }
      }
      if (cleanStart && isSucceeded) {
        if (!succeeded.isCompleted) succeeded.complete();
      } else if (started.isCompleted && isSucceeded) {
        if (!succeeded.isCompleted) succeeded.complete();
      }
    });

    try {
      if (!cleanStart) {
        try {
          await started.future.timeout(const Duration(seconds: 5));
        } catch (e) {
          if (e.runtimeType.toString().contains('TimeoutException')) {
            return;
          }
          rethrow;
        }
      }
      await succeeded.future.timeout(timeout ?? const Duration(minutes: 5));
    } finally {
      await subscription.cancel();
    }

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

  Future<void> _buildDebugExtension() async {
    final process = await Process.run('tool/build_extension.sh', [
      'prod',
    ], workingDirectory: absolutePath(pathFromDwds: 'debug_extension'));
    _logger.info(process.stdout);
  }

  Future<ChromeTab> _fetchDartDebugExtensionTab(
    ChromeConnection connection,
  ) async {
    final extensionTabs = (await connection.getTabs()).where((tab) {
      return tab.isChromeExtension;
    });
    for (final tab in extensionTabs) {
      final tabConnection = await tab.connect();
      final response = await tabConnection.runtime.evaluate(
        'window.isDartDebugExtension',
      );
      if (response.value == true) {
        return tab;
      }
    }
    throw StateError('No extension installed.');
  }

  /// Finds the line number in [scriptRef] matching [breakpointId].
  ///
  /// A breakpoint ID is found by looking for a line that ends with a comment
  /// of exactly this form: `// Breakpoint: <id>`.
  ///
  /// Throws if it can't find the matching line.
  Future<int> findBreakpointLine(
    String breakpointId,
    String isolateId,
    ScriptRef scriptRef,
  ) async {
    final script = await debugConnection.vmService.getObject(
      isolateId,
      scriptRef.id!,
    ) as Script;
    final lines = LineSplitter.split(script.source!).toList();
    final lineNumber = lines.indexWhere(
      (l) => l.endsWith('// Breakpoint: $breakpointId'),
    );
    if (lineNumber == -1) {
      throw StateError(
        'Unable to find breakpoint in ${scriptRef.uri} with id '
        '$breakpointId',
      );
    }
    return lineNumber + 1;
  }
}

typedef Edit = ({String file, String originalString, String newString});
