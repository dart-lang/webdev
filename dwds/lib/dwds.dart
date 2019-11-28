// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build_daemon/data/build_status.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'asset_handler.dart';
import 'src/connections/app_connection.dart';
import 'src/connections/debug_connection.dart';
import 'src/handlers/dev_handler.dart';
import 'src/handlers/injected_handler.dart';
import 'src/servers/devtools.dart';
import 'src/servers/extension_backend.dart';

export 'src/connections/app_connection.dart' show AppConnection;
export 'src/connections/debug_connection.dart' show DebugConnection;
export 'src/handlers/dev_handler.dart' show AppConnectionException;
export 'src/services/chrome_proxy_service.dart' show ChromeDebugException;

typedef LogWriter = void Function(Level, String);
typedef ConnectionProvider = Future<ChromeConnection> Function();
typedef UrlEncoder = Future<String> Function(String url);
enum ReloadConfiguration { none, hotReload, hotRestart, liveReload }
enum ModuleStrategy { requireJS, legacy }

/// The Dart Web Debug Service.
class Dwds {
  final Handler handler;
  final DevTools _devTools;
  final DevHandler _devHandler;
  final bool _enableDebugging;

  Dwds._(this.handler, this._devTools, this._devHandler, this._enableDebugging);

  Stream<AppConnection> get connectedApps => _devHandler.connectedApps;

  StreamController<DebugConnection> get extensionDebugConnections =>
      _devHandler.extensionDebugConnections;

  Future<void> stop() async {
    await _devTools?.close();
    await _devHandler.close();
  }

  Future<DebugConnection> debugConnection(AppConnection appConnection) async {
    if (!_enableDebugging) throw StateError('Debugging is not enabled.');
    var appDebugServices = await _devHandler.loadAppServices(appConnection);
    await appDebugServices.chromeProxyService.isInitialized;
    return DebugConnection(appDebugServices);
  }

  static Future<Dwds> start({
    @required AssetHandler assetHandler,
    @required Stream<BuildResult> buildResults,
    @required ConnectionProvider chromeConnection,
    @required bool enableDebugging,
    String hostname,
    ReloadConfiguration reloadConfiguration,
    bool useSse,
    bool serveDevTools,
    LogWriter logWriter,
    bool verbose,
    bool enableDebugExtension,
    ModuleStrategy moduleStrategy,
    UrlEncoder urlEncoder,
    @deprecated bool restoreBreakpoints,
  }) async {
    hostname ??= 'localhost';
    reloadConfiguration ??= ReloadConfiguration.none;
    enableDebugging ??= true;
    enableDebugExtension ??= false;
    useSse ??= true;
    serveDevTools ??= true;
    logWriter ??= (level, message) => print(message);
    verbose ??= false;
    globalModuleStrategy = moduleStrategy ?? ModuleStrategy.requireJS;
    restoreBreakpoints ??= false;

    var cascade = Cascade();
    var pipeline = const Pipeline();

    DevTools devTools;
    String extensionUri;
    ExtensionBackend extensionBackend;
    if (enableDebugExtension) {
      extensionBackend = await ExtensionBackend.start(hostname);
      extensionUri = Uri(
              scheme: 'http',
              host: hostname,
              port: extensionBackend.port,
              path: r'$debug')
          .toString();
      if (urlEncoder != null) extensionUri = await urlEncoder(extensionUri);
    }

    pipeline = pipeline.addMiddleware(createInjectedHandler(
      reloadConfiguration,
      extensionUri: extensionUri,
      urlEncoder: urlEncoder,
    ));

    if (serveDevTools) {
      devTools = await DevTools.start(hostname);
      var uri =
          Uri(scheme: 'http', host: devTools.hostname, port: devTools.port);
      logWriter(Level.INFO, 'Serving DevTools at $uri\n');
    }
    var devHandler = DevHandler(
      chromeConnection,
      buildResults,
      devTools,
      assetHandler,
      hostname,
      verbose,
      logWriter,
      extensionBackend,
      urlEncoder,
      restoreBreakpoints,
      useSse,
      serveDevTools,
    );
    cascade = cascade.add(devHandler.handler).add(assetHandler.handler);

    return Dwds._(
      pipeline.addHandler(cascade.handler),
      devTools,
      devHandler,
      enableDebugging,
    );
  }
}
