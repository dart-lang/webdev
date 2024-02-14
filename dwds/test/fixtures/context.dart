// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:dwds/asset_reader.dart';
import 'package:dwds/dart_web_debug_service.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/loaders/build_runner_require.dart';
import 'package:dwds/src/loaders/frontend_server_ddc.dart';
import 'package:dwds/src/loaders/frontend_server_require.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/readers/proxy_server_asset_reader.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/services/expression_compiler_service.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/server.dart';
import 'package:file/local.dart';
import 'package:frontend_server_common/src/resident_runner.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';
import 'package:test/test.dart';
import 'package:test_common/logging.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:test_common/utilities.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webdriver/async_io.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'project.dart';
import 'server.dart';
import 'utilities.dart';

final _exeExt = Platform.isWindows ? '.exe' : '';

const isRPCError = TypeMatcher<RPCError>();
const isSentinelException = TypeMatcher<SentinelException>();

final Matcher throwsRPCError = throwsA(isRPCError);
final Matcher throwsSentinelException = throwsA(isSentinelException);

Matcher isRPCErrorWithMessage(String message) =>
    isA<RPCError>().having((e) => e.message, 'message', contains(message));
Matcher throwsRPCErrorWithMessage(String message) =>
    throwsA(isRPCErrorWithMessage(message));

Matcher isRPCErrorWithCode(int code) =>
    isA<RPCError>().having((e) => e.code, 'code', equals(code));
Matcher throwsRPCErrorWithCode(int code) => throwsA(isRPCErrorWithCode(code));

enum CompilationMode { buildDaemon, frontendServer }

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
  late Process? _chromeDriver;

  WebkitDebugger get webkitDebugger => _webkitDebugger!;
  late WebkitDebugger? _webkitDebugger;

  Handler get assetHandler => _assetHandler!;
  late Handler? _assetHandler;

  Client get client => _client!;
  late Client? _client;

  ExpressionCompilerService? ddcService;

  int get port => _port!;
  late int? _port;

  Directory get outputDir => _outputDir!;
  late Directory? _outputDir;

  late WipConnection extensionConnection;
  late AppConnection appConnection;
  late DebugConnection debugConnection;

  final _logger = logging.Logger('Context');

  /// Internal VM service.
  ///
  /// Prefer using [vmService] instead in tests when possible, to include testing
  /// of the VmServerConnection (bypassed when using [service]).
  ChromeProxyService get service => fetchChromeProxyService(debugConnection);

  /// External VM service.
  VmService get vmService => debugConnection.vmService;

  TestContext(this.project, this.sdkConfigurationProvider) {
    DartUri.currentDirectory = project.absolutePackageDirectory;

    project.validate();

    _logger.info(
      'Serving: ${project.directoryToServe}/${project.filePathToServe}',
    );
    _logger.info('Project: ${project.absolutePackageDirectory}');
    _logger.info('Packages: ${project.packageConfigFile}');
    _logger.info('Entry: ${project.dartEntryFilePath}');
  }

  Future<void> setUp({
    TestSettings testSettings = const TestSettings(),
    TestAppMetadata appMetadata = const TestAppMetadata.externalApp(),
    TestDebugSettings debugSettings = const TestDebugSettings.noDevTools(),
  }) async {
    try {
      // Build settings to return from load strategy.
      final buildSettings = TestBuildSettings(
        appEntrypoint: project.dartEntryFilePackageUri,
        canaryFeatures: testSettings.canaryFeatures,
        isFlutterApp: testSettings.isFlutterApp,
        experiments: testSettings.experiments,
      );

      // Make sure configuration was created correctly.
      final sdkLayout = sdkConfigurationProvider.sdkLayout;
      final configuration = await sdkConfigurationProvider.configuration;
      configuration.validate();
      await project.cleanUp();

      DartUri.currentDirectory = project.absolutePackageDirectory;

      configureLogWriter();

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
        _chromeDriver = await Process.start(
          'chromedriver$_exeExt',
          ['--port=$chromeDriverPort', '--url-base=$chromeDriverUrlBase'],
        );
        // On windows this takes a while to boot up, wait for the first line
        // of stdout as a signal that it is ready.
        final stdOutLines = chromeDriver.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();

        final stdErrLines = chromeDriver.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .asBroadcastStream();

        stdOutLines
            .listen((line) => _logger.finest('ChromeDriver stdout: $line'));
        stdErrLines
            .listen((line) => _logger.warning('ChromeDriver stderr: $line'));

        await stdOutLines.first;
      } catch (e) {
        throw StateError(
          'Could not start ChromeDriver. Is it installed?\nError: $e',
        );
      }

      await Process.run(
        sdkLayout.dartPath,
        ['pub', 'upgrade'],
        workingDirectory: project.absolutePackageDirectory,
      );

      ExpressionCompiler? expressionCompiler;
      AssetReader assetReader;
      Stream<BuildResults> buildResults;
      LoadStrategy loadStrategy;
      String basePath = '';
      String filePathToServe = project.filePathToServe;

      _port = await findUnusedPort();
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
              '--verbose',
            ];
            _daemonClient = await connectClient(
                sdkLayout.dartPath, project.absolutePackageDirectory, options,
                (log) {
              final record = log.toLogRecord();
              final name =
                  record.loggerName == '' ? '' : '${record.loggerName}: ';
              _logger.log(
                record.level,
                '$name${record.message}',
                record.error,
                record.stackTrace,
              );
            });
            daemonClient.registerBuildTarget(
              DefaultBuildTarget((b) => b..target = project.directoryToServe),
            );
            daemonClient.startBuild();

            await waitForSuccessfulBuild();

            final assetServerPort =
                daemonPort(project.absolutePackageDirectory);
            _assetHandler = proxyHandler(
              'http://localhost:$assetServerPort/${project.directoryToServe}/',
              client: client,
            );
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

            loadStrategy = BuildRunnerRequireStrategyProvider(
              assetHandler,
              testSettings.reloadConfiguration,
              assetReader,
              buildSettings,
            ).strategy;

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
            final fileSystem = LocalFileSystem();
            final packageUriMapper = await PackageUriMapper.create(
              fileSystem,
              project.packageConfigFile,
              useDebuggerModuleNames: testSettings.useDebuggerModuleNames,
            );

            final compilerOptions = TestCompilerOptions(
              nullSafety: project.nullSafety,
              experiments: buildSettings.experiments,
              canaryFeatures: buildSettings.canaryFeatures,
              moduleFormat: testSettings.moduleFormat,
            );

            _webRunner = ResidentWebRunner(
              mainUri: entry,
              urlTunneler: debugSettings.urlEncoder,
              projectDirectory: p.toUri(project.absolutePackageDirectory),
              packageConfigFile: project.packageConfigFile,
              packageUriMapper: packageUriMapper,
              fileSystemRoots: [p.toUri(project.absolutePackageDirectory)],
              fileSystemScheme: 'org-dartlang-app',
              outputPath: outputDir.path,
              compilerOptions: compilerOptions,
              sdkLayout: sdkLayout,
              verbose: testSettings.verboseCompiler,
            );

            final assetServerPort = await findUnusedPort();
            await webRunner.run(
              fileSystem,
              appMetadata.hostname,
              assetServerPort,
              filePathToServe,
            );

            if (testSettings.enableExpressionEvaluation) {
              expressionCompiler = webRunner.expressionCompiler;
            }

            basePath = webRunner.devFS.assetServer.basePath;
            assetReader = webRunner.devFS.assetServer;
            _assetHandler = webRunner.devFS.assetServer.handleRequest;
            loadStrategy = switch (testSettings.moduleFormat) {
              ModuleFormat.amd => FrontendServerRequireStrategyProvider(
                  testSettings.reloadConfiguration,
                  assetReader,
                  packageUriMapper,
                  () async => {},
                  buildSettings,
                ).strategy,
              ModuleFormat.ddc => FrontendServerDdcStrategyProvider(
                  testSettings.reloadConfiguration,
                  assetReader,
                  packageUriMapper,
                  () async => {},
                  buildSettings,
                ).strategy,
              _ => throw Exception(
                  'Unsupported DDC module format ${testSettings.moduleFormat.name}.',
                )
            };
            buildResults = const Stream<BuildResults>.empty();
          }
          break;
        default:
          throw Exception(
            'Unsupported compilation mode: ${testSettings.compilationMode}',
          );
      }

      final debugPort = await findUnusedPort();
      if (testSettings.launchChrome) {
        // If the environment variable DWDS_DEBUG_CHROME is set to the string true
        // then Chrome will be launched with a UI rather than headless.
        // If the extension is enabled, then Chrome will be launched with a UI
        // since headless Chrome does not support extensions.
        final enableDebugExtension = debugSettings.enableDebugExtension;
        final headless = Platform.environment['DWDS_DEBUG_CHROME'] != 'true' &&
            !enableDebugExtension;
        if (enableDebugExtension) {
          await _buildDebugExtension();
        }
        final capabilities = Capabilities.chrome
          ..addAll({
            Capabilities.chromeOptions: {
              'args': [
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
      final tabConnectionCompleter = Completer();
      final appConnectionCompleter = Completer();
      final connection = ChromeConnection('localhost', debugPort);

      _testServer = await TestServer.start(
        debugSettings:
            debugSettings.copyWith(expressionCompiler: expressionCompiler),
        appMetadata: appMetadata,
        port: port,
        assetHandler: assetHandler,
        assetReader: assetReader,
        strategy: loadStrategy,
        target: project.directoryToServe,
        buildResults: buildResults,
        chromeConnection: () async => connection,
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
          await tabConnection.debugger
              .enable()
              .then((_) => tabConnectionCompleter.complete());
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
      } else {
        // No tab needs to be dicovered, so fulfill the relevant completer.
        tabConnectionCompleter.complete();
      }
    } catch (e, s) {
      _logger.severe('Failed to setup the service, $e:$s');
      await tearDown();
      rethrow;
    }
  }

  Future<void> startDebugging() async {
    debugConnection = await testServer.dwds.debugConnection(appConnection);
    _webkitDebugger = WebkitDebugger(WipDebugger(tabConnection));
  }

  Future<void> tearDown() async {
    await _webDriver?.quit(closeSession: true);
    _chromeDriver?.kill();
    DartUri.currentDirectory = p.current;
    await _daemonClient?.close();
    await ddcService?.stop();
    await _webRunner?.stop();
    await _testServer?.stop();
    _client?.close();
    await _outputDir?.delete(recursive: true);
    stopLogWriter();

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

  void makeEditToDartEntryFile({
    required String toReplace,
    required String replaceWith,
  }) {
    final file = File(project.dartEntryFilePath);
    final fileContents = file.readAsStringSync();
    file.writeAsStringSync(fileContents.replaceAll(toReplace, replaceWith));
  }

  void makeEditToDartLibFile({
    required String libFileName,
    required String toReplace,
    required String replaceWith,
  }) {
    final file = File(project.dartLibFilePath(libFileName));
    final fileContents = file.readAsStringSync();
    file.writeAsStringSync(fileContents.replaceAll(toReplace, replaceWith));
  }

  Future<void> waitForSuccessfulBuild({
    Duration? timeout,
    bool propagateToBrowser = false,
  }) async {
    // Wait for the build until the timeout is reached:
    await daemonClient.buildResults
        .firstWhere(
          (results) => results.results
              .any((result) => result.status == BuildStatus.succeeded),
        )
        .timeout(timeout ?? const Duration(seconds: 60));

    if (propagateToBrowser) {
      // Allow change to propagate to the browser.
      // Windows, or at least Travis on Windows, seems to need more time.
      final delay = Platform.isWindows
          ? const Duration(seconds: 5)
          : const Duration(seconds: 2);
      await Future.delayed(delay);
    }
  }

  Future<void> _buildDebugExtension() async {
    final process = await Process.run(
      'tool/build_extension.sh',
      ['prod'],
      workingDirectory: absolutePath(pathFromDwds: 'debug_extension'),
    );
    print(process.stdout);
  }

  Future<ChromeTab> _fetchDartDebugExtensionTab(
    ChromeConnection connection,
  ) async {
    final extensionTabs = (await connection.getTabs()).where((tab) {
      return tab.isChromeExtension;
    });
    for (var tab in extensionTabs) {
      final tabConnection = await tab.connect();
      final response =
          await tabConnection.runtime.evaluate('window.isDartDebugExtension');
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
    final script = await debugConnection.vmService
        .getObject(isolateId, scriptRef.id!) as Script;
    final lines = LineSplitter.split(script.source!).toList();
    final lineNumber =
        lines.indexWhere((l) => l.endsWith('// Breakpoint: $breakpointId'));
    if (lineNumber == -1) {
      throw StateError('Unable to find breakpoint in ${scriptRef.uri} with id '
          '$breakpointId');
    }
    return lineNumber + 1;
  }
}
