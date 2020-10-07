// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'data/build_result.dart';
import 'src/connections/app_connection.dart';
import 'src/connections/debug_connection.dart';
import 'src/debugging/metadata/provider.dart';
import 'src/handlers/dev_handler.dart';
import 'src/handlers/injector.dart';
import 'src/handlers/socket_connections.dart';
import 'src/loaders/strategy.dart';
import 'src/readers/asset_reader.dart';
import 'src/servers/devtools.dart';
import 'src/servers/extension_backend.dart';
import 'src/services/expression_compiler.dart';
import 'src/utilities/shared.dart';

export 'src/connections/app_connection.dart' show AppConnection;
export 'src/connections/debug_connection.dart' show DebugConnection;
export 'src/debugging/metadata/provider.dart' show MetadataProvider;
export 'src/handlers/dev_handler.dart' show AppConnectionException;
export 'src/handlers/socket_connections.dart';
export 'src/loaders/build_runner_require.dart'
    show BuildRunnerRequireStrategyProvider;
export 'src/loaders/frontend_server_require.dart'
    show FrontendServerRequireStrategyProvider;
export 'src/loaders/legacy.dart' show LegacyStrategy;
export 'src/loaders/require.dart' show RequireStrategy;
export 'src/loaders/strategy.dart' show LoadStrategy, ReloadConfiguration;
export 'src/readers/asset_reader.dart' show AssetReader;
export 'src/readers/frontend_server_asset_reader.dart'
    show FrontendServerAssetReader;
export 'src/readers/proxy_server_asset_reader.dart' show ProxyServerAssetReader;
export 'src/services/chrome_proxy_service.dart' show ChromeDebugException;
export 'src/services/expression_compiler.dart'
    show ExpressionCompilationResult, ExpressionCompiler;
export 'src/services/expression_compiler_service.dart'
    show ExpressionCompilerService;
export 'src/utilities/shared.dart' show LogWriter;

typedef ConnectionProvider = Future<ChromeConnection> Function();
typedef UrlEncoder = Future<String> Function(String url);

/// The Dart Web Debug Service.
class Dwds {
  final Middleware middleware;
  final Handler handler;
  final DevTools _devTools;
  final DevHandler _devHandler;
  final AssetReader _assetReader;
  final bool _enableDebugging;

  Dwds._(
    this.middleware,
    this._devTools,
    this._devHandler,
    this._assetReader,
    this._enableDebugging,
  ) : handler = _devHandler.handler;

  Stream<AppConnection> get connectedApps => _devHandler.connectedApps;

  StreamController<DebugConnection> get extensionDebugConnections =>
      _devHandler.extensionDebugConnections;

  Future<void> stop() async {
    await _devTools?.close();
    await _devHandler.close();
    await _assetReader.close();
  }

  Future<DebugConnection> debugConnection(AppConnection appConnection) async {
    if (!_enableDebugging) throw StateError('Debugging is not enabled.');
    var appDebugServices = await _devHandler.loadAppServices(appConnection);
    await appDebugServices.chromeProxyService.isInitialized;
    return DebugConnection(appDebugServices);
  }

  static Future<Dwds> start({
    @required AssetReader assetReader,
    @required Stream<BuildResult> buildResults,
    @required ConnectionProvider chromeConnection,
    @required LoadStrategy loadStrategy,
    @required bool enableDebugging,
    @required MetadataProvider metadataProvider,
    bool enableDebugExtension,
    String hostname,
    bool useSseForDebugProxy,
    bool useSseForDebugBackend,
    bool serveDevTools,
    LogWriter logWriter,
    bool verbose,
    UrlEncoder urlEncoder,
    bool spawnDds = true,
    // TODO(annagrin): make expressionCompiler argument required
    // [issue 881](https://github.com/dart-lang/webdev/issues/881)
    ExpressionCompiler expressionCompiler,
  }) async {
    hostname ??= 'localhost';
    enableDebugging ??= true;
    enableDebugExtension ??= false;
    useSseForDebugProxy ??= true;
    useSseForDebugBackend ??= true;
    serveDevTools ??= true;
    logWriter ??= (level, message) => print(message);
    verbose ??= false;
    globalLoadStrategy = loadStrategy;

    DevTools devTools;
    String extensionUri;
    ExtensionBackend extensionBackend;
    if (enableDebugExtension) {
      final handler = useSseForDebugBackend
          ? SseSocketHandler(SseHandler(Uri.parse('/\$debug'),
              keepAlive: const Duration(seconds: 30)))
          : WebSocketSocketHandler();

      extensionBackend = await ExtensionBackend.start(handler, hostname);
      extensionUri = Uri(
              scheme: useSseForDebugBackend ? 'http' : 'ws',
              host: extensionBackend.hostname,
              port: extensionBackend.port,
              path: r'$debug')
          .toString();
      if (urlEncoder != null) extensionUri = await urlEncoder(extensionUri);
    }

    if (serveDevTools) {
      devTools = await DevTools.start(hostname);
      var uri =
          Uri(scheme: 'http', host: devTools.hostname, port: devTools.port);
      logWriter(Level.INFO, 'Serving DevTools at $uri\n');
    }

    var injected = DwdsInjector(
      loadStrategy,
      extensionUri: extensionUri,
    );

    var devHandler = DevHandler(
      chromeConnection,
      buildResults,
      devTools,
      assetReader,
      loadStrategy,
      metadataProvider,
      hostname,
      verbose,
      logWriter,
      extensionBackend,
      urlEncoder,
      useSseForDebugProxy,
      serveDevTools,
      expressionCompiler,
      injected,
      spawnDds,
    );

    return Dwds._(
      injected.middleware,
      devTools,
      devHandler,
      assetReader,
      enableDebugging,
    );
  }
}
