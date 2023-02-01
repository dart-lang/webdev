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
import 'package:dwds/expression_compiler.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/loaders/build_runner_require.dart';
import 'package:dwds/src/loaders/frontend_server_require.dart';
import 'package:dwds/src/loaders/require.dart';
import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/readers/proxy_server_asset_reader.dart';
import 'package:dwds/src/services/expression_compiler_service.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:file/local.dart';
import 'package:frontend_server_common/src/resident_runner.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';
import 'package:logging/logging.dart' as logging;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
// ignore: deprecated_member_use
import 'package:webdriver/io.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'logging.dart';
import 'server.dart';
import 'utilities.dart';

final _exeExt = Platform.isWindows ? '.exe' : '';

const isRPCError = TypeMatcher<RPCError>();
const isSentinelException = TypeMatcher<SentinelException>();

final Matcher throwsRPCError = throwsA(isRPCError);
final Matcher throwsSentinelException = throwsA(isSentinelException);

enum CompilationMode { buildDaemon, frontendServer }

enum IndexBaseMode { noBase, base }

enum NullSafety { weak, sound }

class TestContext {
  final String packageName;
  final String webAssetsPath;
  final String dartEntryFileName;
  final String htmlEntryFileName;
  final NullSafety nullSafety;

  /// Top level directory in which we run the test server, e.g.
  /// "/workstation/webdev/fixtures/_testSound".
  String get workingDirectory => absolutePath(pathFromFixtures: packageName);

  /// The directory to build and serve, e.g. "example".
  String get directoryToServe => p.split(webAssetsPath).first;

  /// The path to the HTML file to serve, relative to the [directoryToServe],
  /// e.g. "hello_world/index.html".
  String get filePathToServe {
    final pathParts = p.split(webAssetsPath).where(
          (pathPart) => pathPart != directoryToServe,
        );
    return webCompatiblePath([...pathParts, htmlEntryFileName]);
  }

  /// The path to the Dart entry file, e.g,
  /// "/workstation/webdev/fixtures/_testSound/example/hello_world/main.dart":
  String get _dartEntryFilePath => absolutePath(
        pathFromFixtures: p.joinAll(
          [packageName, webAssetsPath, dartEntryFileName],
        ),
      );

  /// The URI for the package_config.json is located in:
  /// <project directory>/.dart_tool/package_config
  Uri get _packageConfigFile =>
      p.toUri(p.join(workingDirectory, '.dart_tool', 'package_config.json'));

  String get appUrl => _appUrl!;
  late String? _appUrl;

  WipConnection get tabConnection => _tabConnection!;
  late WipConnection? _tabConnection;

  TestServer get testServer => _testServer!;
  TestServer? _testServer;

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

  TestContext.withSoundNullSafety({
    String packageName = '_testSound',
    String webAssetsPath = 'example/hello_world',
    String dartEntryFileName = 'main.dart',
    String htmlEntryFileName = 'index.html',
  }) : this._(
          nullSafety: NullSafety.sound,
          packageName: packageName,
          webAssetsPath: webAssetsPath,
          dartEntryFileName: dartEntryFileName,
          htmlEntryFileName: htmlEntryFileName,
        );

  TestContext.withWeakNullSafety({
    String packageName = '_test',
    String webAssetsPath = 'example/hello_world',
    String dartEntryFileName = 'main.dart',
    String htmlEntryFileName = 'index.html',
  }) : this._(
          nullSafety: NullSafety.weak,
          packageName: packageName,
          webAssetsPath: webAssetsPath,
          dartEntryFileName: dartEntryFileName,
          htmlEntryFileName: htmlEntryFileName,
        );

  TestContext._({
    required this.packageName,
    required this.webAssetsPath,
    required this.dartEntryFileName,
    required this.htmlEntryFileName,
    required this.nullSafety,
  }) {
    // Verify that the test fixtures package matches the null-safety mode:
    final isSoundPackage = packageName.toLowerCase().contains('sound');
    assert(nullSafety == NullSafety.sound ? isSoundPackage : !isSoundPackage);
    // Verify that the web assets path has no starting slash:
    assert(!webAssetsPath.startsWith('/'));

    DartUri.currentDirectory = workingDirectory;

    _logger.info('Serving: $directoryToServe/$filePathToServe');
    _logger.info('Project: $workingDirectory');
    _logger.info('Packages: $_packageConfigFile');
    _logger.info('Entry: $_dartEntryFilePath');
  }

  Future<void> setUp({
    ReloadConfiguration reloadConfiguration = ReloadConfiguration.none,
    bool serveDevTools = false,
    bool enableDebugExtension = false,
    bool autoRun = true,
    bool enableDebugging = true,
    bool useSse = true,
    bool spawnDds = true,
    String hostname = 'localhost',
    bool waitToDebug = false,
    UrlEncoder? urlEncoder,
    CompilationMode compilationMode = CompilationMode.buildDaemon,
    bool enableExpressionEvaluation = false,
    bool verboseCompiler = false,
    bool useDebuggerModuleNames = false,
    bool launchChrome = true,
    bool isFlutterApp = false,
    bool isInternalBuild = false,
  }) async {
    // Generate missing SDK assets if needed.
    final sdkConfigurationProvider =
        TestSdkConfigurationProvider(verboseCompiler: verboseCompiler);
    final configuration = await sdkConfigurationProvider.configuration;
    configuration.validate();

    try {
      DartUri.currentDirectory = workingDirectory;
      configureLogWriter();

      _client = IOClient(HttpClient()
        ..maxConnectionsPerHost = 200
        ..idleTimeout = const Duration(seconds: 30)
        ..connectionTimeout = const Duration(seconds: 30));

      final systemTempDir = Directory.systemTemp;
      _outputDir = systemTempDir.createTempSync('foo bar');

      final chromeDriverPort = await findUnusedPort();
      final chromeDriverUrlBase = 'wd/hub';
      try {
        _chromeDriver = await Process.start('chromedriver$_exeExt',
            ['--port=$chromeDriverPort', '--url-base=$chromeDriverUrlBase']);
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
            'Could not start ChromeDriver. Is it installed?\nError: $e');
      }

      await Process.run(dartPath, ['pub', 'upgrade'],
          workingDirectory: workingDirectory);

      ExpressionCompiler? expressionCompiler;
      AssetReader assetReader;
      Stream<BuildResults> buildResults;
      RequireStrategy requireStrategy;
      String basePath = '';

      _port = await findUnusedPort();
      switch (compilationMode) {
        case CompilationMode.buildDaemon:
          {
            final options = [
              if (enableExpressionEvaluation) ...[
                '--define',
                'build_web_compilers|ddc=generate-full-dill=true',
              ],
              '--verbose',
            ];
            _daemonClient =
                await connectClient(workingDirectory, options, (log) {
              final record = log.toLogRecord();
              final name =
                  record.loggerName == '' ? '' : '${record.loggerName}: ';
              _logger.log(record.level, '$name${record.message}', record.error,
                  record.stackTrace);
            });
            daemonClient.registerBuildTarget(
                DefaultBuildTarget((b) => b..target = directoryToServe));
            daemonClient.startBuild();

            await waitForSuccessfulBuild();

            final assetServerPort = daemonPort(workingDirectory);
            _assetHandler = proxyHandler(
                'http://localhost:$assetServerPort/$directoryToServe/',
                client: client);
            assetReader =
                ProxyServerAssetReader(assetServerPort, root: directoryToServe);

            if (enableExpressionEvaluation) {
              ddcService = ExpressionCompilerService(
                'localhost',
                port,
                verbose: verboseCompiler,
                sdkConfigurationProvider: sdkConfigurationProvider,
              );
              expressionCompiler = ddcService;
            }

            requireStrategy = BuildRunnerRequireStrategyProvider(
              assetHandler,
              reloadConfiguration,
              assetReader,
            ).strategy;

            buildResults = daemonClient.buildResults;
          }
          break;
        case CompilationMode.frontendServer:
          {
            _logger.warning('Index: $filePathToServe');

            final entry = p.toUri(p.join(webAssetsPath, dartEntryFileName));
            final fileSystem = LocalFileSystem();
            final packageUriMapper = await PackageUriMapper.create(
              fileSystem,
              _packageConfigFile,
              useDebuggerModuleNames: useDebuggerModuleNames,
            );

            _webRunner = ResidentWebRunner(
              entry,
              urlEncoder,
              p.toUri(workingDirectory),
              _packageConfigFile,
              packageUriMapper,
              [p.toUri(workingDirectory)],
              'org-dartlang-app',
              outputDir.path,
              nullSafety == NullSafety.sound,
              verboseCompiler,
            );

            final assetServerPort = await findUnusedPort();
            await webRunner.run(fileSystem, hostname, assetServerPort,
                p.join(directoryToServe, filePathToServe));

            if (enableExpressionEvaluation) {
              expressionCompiler = webRunner.expressionCompiler;
            }

            basePath = webRunner.devFS.assetServer.basePath;
            assetReader = webRunner.devFS.assetServer;
            _assetHandler = webRunner.devFS.assetServer.handleRequest;

            requireStrategy = FrontendServerRequireStrategyProvider(
                    reloadConfiguration,
                    assetReader,
                    packageUriMapper,
                    () async => {},
                    basePath)
                .strategy;

            buildResults = const Stream<BuildResults>.empty();
          }
          break;
        default:
          throw Exception('Unsupported compilation mode: $compilationMode');
      }

      final debugPort = await findUnusedPort();
      if (launchChrome) {
        // If the environment variable DWDS_DEBUG_CHROME is set to the string true
        // then Chrome will be launched with a UI rather than headless.
        // If the extension is enabled, then Chrome will be launched with a UI
        // since headless Chrome does not support extensions.
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
                if (headless) '--headless'
              ]
            }
          });
        _webDriver = await createDriver(
            spec: WebDriverSpec.JsonWire,
            desired: capabilities,
            uri: Uri.parse(
                'http://127.0.0.1:$chromeDriverPort/$chromeDriverUrlBase/'));
      }
      final connection = ChromeConnection('localhost', debugPort);

      _testServer = await TestServer.start(
        hostname,
        port,
        assetHandler,
        assetReader,
        requireStrategy,
        directoryToServe,
        buildResults,
        () async => connection,
        serveDevTools,
        enableDebugExtension,
        autoRun,
        enableDebugging,
        useSse,
        urlEncoder,
        expressionCompiler,
        spawnDds,
        ddcService,
        isFlutterApp,
        isInternalBuild,
        sdkConfigurationProvider,
      );

      _appUrl = basePath.isEmpty
          ? 'http://localhost:$port/$filePathToServe'
          : 'http://localhost:$port/$basePath/$filePathToServe';

      if (launchChrome) {
        await _webDriver?.get(appUrl);
        final tab = await connection.getTab((t) => t.url == appUrl);
        if (tab != null) {
          _tabConnection = await tab.connect();
          await tabConnection.runtime.enable();
          await tabConnection.debugger.enable();
        } else {
          throw StateError('Unable to connect to tab.');
        }

        if (enableDebugExtension) {
          final extensionTab = await _fetchDartDebugExtensionTab(connection);
          extensionConnection = await extensionTab.connect();
          await extensionConnection.runtime.enable();
        }

        appConnection = await testServer.dwds.connectedApps.first;
        if (enableDebugging && !waitToDebug) {
          await startDebugging();
        }
      }
    } catch (e) {
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
  }) async {
    final file = File(_dartEntryFilePath);
    final fileContents = file.readAsStringSync();
    file.writeAsStringSync(fileContents.replaceAll(toReplace, replaceWith));
  }

  Future<void> waitForSuccessfulBuild(
      {Duration? timeout, bool propagateToBrowser = false}) async {
    // Wait for the build until the timeout is reached:
    await daemonClient.buildResults
        .firstWhere((results) => results.results
            .any((result) => result.status == BuildStatus.succeeded))
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
    final process = await Process.run('tool/build_extension.sh', ['prod'],
        workingDirectory: absolutePath(pathFromDwds: 'debug_extension'));
    print(process.stdout);
  }

  Future<ChromeTab> _fetchDartDebugExtensionTab(
      ChromeConnection connection) async {
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
      String breakpointId, String isolateId, ScriptRef scriptRef) async {
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
