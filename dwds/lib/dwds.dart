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

import 'src/connections/app_connection.dart';
import 'src/connections/debug_connection.dart';
import 'src/handlers/asset_handler.dart';
import 'src/handlers/dev_handler.dart';
import 'src/handlers/injected_handler.dart';
import 'src/servers/devtools.dart';
import 'src/servers/extension_backend.dart';

export 'src/connections/app_connection.dart' show AppConnection;
export 'src/connections/debug_connection.dart' show DebugConnection;

typedef LogWriter = void Function(Level, String);
typedef ConnectionProvider = Future<ChromeConnection> Function();
enum ReloadConfiguration { none, hotReload, hotRestart, liveReload }
enum ModuleStrategy { requireJS, legacy }

/// The Dart Web Debug Service.
class Dwds {
  final Handler handler;
  final DevTools _devTools;
  final DevHandler _devHandler;

  Dwds._(this.handler, this._devTools, this._devHandler);

  Stream<AppConnection> get connectedApps => _devHandler.connectedApps;

  Future<void> stop() async {
    await _devTools?.close();
    await _devHandler.close();
  }

  Future<DebugConnection> debugConnection(AppConnection appConnection) async {
    var appDebugServices = await _devHandler.loadAppServices(
        appConnection.request.appId, appConnection.request.instanceId);
    return DebugConnection(appDebugServices);
  }

  Future<DebugConnection> extensionDebugConnection(AppConnection appConnection) async {
    var appDebugServices = await _devHandler.appServicesStream.stream.first;
    return DebugConnection(appDebugServices);
  }

  static Future<Dwds> start({
    @required int applicationPort,
    @required int assetServerPort,
    @required String applicationTarget,
    @required Stream<BuildResult> buildResults,
    @required ConnectionProvider chromeConnection,
    String hostname,
    ReloadConfiguration reloadConfiguration,
    bool serveDevTools,
    LogWriter logWriter,
    bool verbose,
    bool enableDebugExtension,
    ModuleStrategy moduleStrategy,
  }) async {
    hostname ??= 'localhost';
    reloadConfiguration ??= ReloadConfiguration.none;
    enableDebugExtension ??= false;
    // `serveDevTools` is true by default when the extension is enabled.
    serveDevTools = serveDevTools || enableDebugExtension;
    logWriter ??= (level, message) => print(message);
    verbose ??= false;
    globalModuleStrategy = moduleStrategy ?? ModuleStrategy.requireJS;
    var assetHandler = AssetHandler(
      assetServerPort,
      applicationTarget,
      hostname,
      applicationPort,
    );
    var cascade = Cascade();
    var pipeline = const Pipeline();

    DevTools devTools;
    String extensionHostname;
    int extensionPort;
    ExtensionBackend extensionBackend;
    if (enableDebugExtension) {
      extensionBackend = await ExtensionBackend.start(hostname);
      extensionHostname = extensionBackend.hostname;
      extensionPort = extensionBackend.port;
    }

    pipeline = pipeline.addMiddleware(createInjectedHandler(reloadConfiguration,
        extensionHostname: extensionHostname, extensionPort: extensionPort));

    if (serveDevTools) {
      devTools = await DevTools.start(hostname);
      logWriter(Level.INFO,
          'Serving DevTools at ${Uri(scheme: 'http', host: devTools.hostname, port: devTools.port)}\n');
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
    );
    cascade = cascade.add(devHandler.handler).add(assetHandler.handler);

    return Dwds._(pipeline.addHandler(cascade.handler), devTools, devHandler);
  }
}
