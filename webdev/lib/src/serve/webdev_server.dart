// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_daemon/data/build_status.dart' as daemon;
import 'package:dwds/data/build_result.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/sdk_configuration.dart';
import 'package:file/local.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http_multi_server/http_multi_server.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

import '../command/configuration.dart';
import '../util.dart';
import 'chrome.dart';
import 'handlers/favicon_handler.dart';
import 'utils.dart' show findPackageConfigFilePath, findPackageConfigUri;

Logger _logger = Logger('WebDevServer');

const reloadedSourcesFileName = 'reloaded_sources.json';
const jsLibraryBundleExtension = '.ddc.js';
const multiRootScheme = 'org-dartlang-app';

class ServerOptions {
  final Configuration configuration;
  final int port;
  final String target;
  final int daemonPort;

  ServerOptions(this.configuration, this.port, this.target, this.daemonPort);
}

class WebDevServer {
  final HttpServer _server;
  final http.Client _client;
  final String _protocol;

  final Stream<BuildResult> buildResults;

  /// Can be null if client.js injection is disabled.
  final Dwds? dwds;

  final ExpressionCompilerService? ddcService;

  final String target;

  WebDevServer._(
    this.target,
    this._server,
    this._client,
    this._protocol,
    this.buildResults,
    bool autoRun, {
    this.dwds,
    this.ddcService,
  }) {
    if (autoRun) {
      dwds?.connectedApps.listen((connection) {
        connection.runMain();
      });
    }
  }

  String get host => _server.address.host;
  int get port => _server.port;
  String get protocol => _protocol;

  Future<void> stop() async {
    await dwds?.stop();
    await ddcService?.stop();
    await _server.close(force: true);
    _client.close();
  }

  static Future<WebDevServer> start(
    ServerOptions options,
    Stream<daemon.BuildResults> buildResults,
  ) async {
    final basePath = 'http://localhost:${options.port}';
    var pipeline = const Pipeline();

    if (options.configuration.logRequests) {
      pipeline = pipeline.addMiddleware(logRequests());
    }

    pipeline = pipeline.addMiddleware(interceptFavicon);

    /// JSON-ifiable list of sources that were reloaded in this restart and
    /// follows the following format:
    ///
    /// `src`: A string that corresponds to the file path containing a DDC library
    /// bundle. To support embedded libraries, the path should include the
    /// `baseUri` of the web server.
    /// `module`: The name of the library bundle in `src`.
    /// `libraries`: An array of strings containing the libraries that were
    /// compiled in `src`.
    ///
    /// For example:
    /// ```json
    /// [
    ///   {
    ///     "src": "<baseUri>/<file_name>",
    ///     "module": "<module_name>",
    ///     "libraries": ["<lib1>", "<lib2>"],
    ///   },
    /// ]
    /// ```
    ///
    /// The path of the output file should stay consistent across the lifetime of
    /// the app.
    final reloadedSources = <Map<String, dynamic>>[];

    // Only provide relevant build results
    final filteredBuildResults = buildResults.asyncMap<BuildResult>((results) {
      if (options.configuration.canaryFeatures) {
        // Clear reloaded sources for the new build results.
        reloadedSources.clear();
        results.changedAssets?.forEach((uri) {
          if (uri.path.endsWith(jsLibraryBundleExtension)) {
            final reloadedSource = {
              'src': ddcUriToSourceUrl(basePath, options.target, uri),
              'module': ddcUriToLibraryId(uri),
              'libraries': [ddcUriToLibraryId(uri)],
            };
            reloadedSources.add(reloadedSource);
          }
        });
      }
      final result = results.results.firstWhere(
        (result) => result.target == options.target,
      );
      switch (result.status) {
        case daemon.BuildStatus.started:
          return BuildResult(status: BuildStatus.started);
        case daemon.BuildStatus.failed:
          return BuildResult(status: BuildStatus.failed);
        case daemon.BuildStatus.succeeded:
          return BuildResult(status: BuildStatus.succeeded);
        default:
          break;
      }
      throw StateError('Unexpected Daemon build result: $result');
    });

    var cascade = Cascade();
    final client = IOClient(
      HttpClient()
        ..maxConnectionsPerHost = 200
        ..idleTimeout = const Duration(seconds: 30)
        ..connectionTimeout = const Duration(seconds: 30),
    );
    final assetHandler = proxyHandler(
      'http://localhost:${options.daemonPort}/${options.target}/',
      client: client,
    );

    Dwds? dwds;
    ExpressionCompilerService? ddcService;
    if (options.configuration.enableInjectedClient) {
      final assetReader = ProxyServerAssetReader(
        options.daemonPort,
        root: options.target,
      );

      // TODO(https://github.com/flutter/devtools/issues/5350): Figure out how
      // to determine the build settings from the build.
      // Can we save build metadata in build_web_compilers and and read it in
      // the load strategy?
      final buildSettings = BuildSettings(
        appEntrypoint: Uri.parse(
          '$multiRootScheme:///${options.target}/main.dart',
        ),
        canaryFeatures: options.configuration.canaryFeatures,
        isFlutterApp: false,
        experiments: options.configuration.experiments,
      );

      final LoadStrategy loadStrategy;
      if (options.configuration.canaryFeatures) {
        final frontendServerFileSystem = LocalFileSystem();
        final packageUriMapper = await PackageUriMapper.create(
          frontendServerFileSystem,
          findPackageConfigUri()!,
          useDebuggerModuleNames: false,
        );
        loadStrategy = FrontendServerDdcLibraryBundleStrategyProvider(
          options.configuration.reload,
          assetReader,
          packageUriMapper,
          () async => {},
          buildSettings,
          packageConfigPath: findPackageConfigFilePath(),
          reloadedSourcesUri: Uri.parse('$basePath/$reloadedSourcesFileName'),
          injectScriptLoad: false,
        ).strategy;
      } else {
        loadStrategy = BuildRunnerRequireStrategyProvider(
          assetHandler,
          options.configuration.reload,
          assetReader,
          buildSettings,
          packageConfigPath: findPackageConfigFilePath(),
        ).strategy;
      }

      if (options.configuration.enableExpressionEvaluation) {
        ddcService = ExpressionCompilerService(
          options.configuration.hostname,
          options.port,
          verbose: options.configuration.verbose,
          sdkConfigurationProvider: const DefaultSdkConfigurationProvider(),
        );
      }
      final shouldServeDevTools =
          options.configuration.debug || options.configuration.debugExtension;

      final debugSettings = DebugSettings(
        enableDebugExtension: options.configuration.debugExtension,
        enableDebugging: options.configuration.debug,
        ddsConfiguration: DartDevelopmentServiceConfiguration(
          enable: !options.configuration.disableDds,
          serveDevTools: shouldServeDevTools,
        ),
        expressionCompiler: ddcService,
      );

      final appMetadata = AppMetadata(hostname: options.configuration.hostname);

      final toolConfiguration = ToolConfiguration(
        loadStrategy: loadStrategy,
        debugSettings: debugSettings,
        appMetadata: appMetadata,
      );
      dwds = await Dwds.start(
        toolConfiguration: toolConfiguration,
        assetReader: assetReader,
        buildResults: filteredBuildResults,
        chromeConnection: () async =>
            (await Chrome.connectedInstance).chromeConnection,
      );
      pipeline = pipeline.addMiddleware(dwds.middleware);
      cascade = cascade.add(dwds.handler);
      if (options.configuration.canaryFeatures) {
        // Add a handler to serve reloaded sources.
        cascade = cascade.add((Request request) {
          if (request.url.path == reloadedSourcesFileName) {
            return Response.ok(
              jsonEncode(reloadedSources),
              headers: {'Content-Type': 'application/json'},
            );
          }
          return Response.notFound('');
        });
      }
      cascade = cascade.add(assetHandler);
    } else {
      cascade = cascade.add(assetHandler);
    }

    final hostname = options.configuration.hostname;
    final tlsCertChain = options.configuration.tlsCertChain ?? '';
    final tlsCertKey = options.configuration.tlsCertKey ?? '';

    HttpServer server;
    final protocol = (tlsCertChain.isNotEmpty && tlsCertKey.isNotEmpty)
        ? 'https'
        : 'http';
    if (protocol == 'https') {
      final serverContext = SecurityContext()
        ..useCertificateChain(tlsCertChain)
        ..usePrivateKey(tlsCertKey);
      server = await HttpMultiServer.bindSecure(
        hostname,
        options.port,
        serverContext,
      );
    } else {
      server = await HttpMultiServer.bind(hostname, options.port);
    }

    serveHttpRequests(server, pipeline.addHandler(cascade.handler), (e, s) {
      _logger.warning('Error serving requests', e, s);
    });

    return WebDevServer._(
      options.target,
      server,
      client,
      protocol,
      filteredBuildResults,
      options.configuration.autoRun,
      dwds: dwds,
      ddcService: ddcService,
    );
  }
}

/// Transforms a package:build JS asset id [uri] into a source url compatible
/// with DDC's bootstrapper.
///
/// [basePath] is the path from which JS files as served up to but not
/// including the path.
/// [target] is the path whose files will be served from [basePath].
/// [uri] is the asset id's uri being transformed.
///
/// Example:
/// basePath: http://localhost:8080
/// target: web
///
/// uri: asset:some_package/web/main.ddc.js
/// returns http://localhost:8080/main.ddc.js
///
/// uri: package:some_package/src/sub_dir/file.ddc.js
/// returns http://localhost:8080/some_package/src/sub_dir/file.ddc.js
String ddcUriToSourceUrl(String basePath, String target, Uri uri) {
  String jsPath;
  if (uri.isScheme('asset')) {
    // This indicates that this asset is the 'main' web asset. We directly
    // serve all files under the package's [target] directory.
    var pathParts = uri.pathSegments.skip(1);
    if (pathParts.first == target) {
      pathParts = pathParts.skip(1);
    }
    jsPath = pathParts.join('/');
  } else if (uri.isScheme('package')) {
    jsPath = 'packages/${uri.path}';
  } else {
    jsPath = uri.path;
  }
  return '$basePath/$jsPath';
}

/// Transforms a package:build JS asset id [uri] into a library id compatible
/// with DDC's bootstrapper.
///
/// Example:
/// uri: asset:some_package/web/main.ddc.js
/// returns org-dartlang-app:///web/main.dart
///
/// uri: package:some_package/src/sub_dir/file.ddc.js
/// returns package:some_package/src/sub_dir/file.dart
String ddcUriToLibraryId(Uri uri) {
  final jsPath = uri.isScheme('package')
      ? 'package:${uri.path}'
      : '$multiRootScheme:///${uri.path}';
  final prefix = jsPath.substring(
    0,
    jsPath.length - jsLibraryBundleExtension.length,
  );
  return '$prefix.dart';
}
