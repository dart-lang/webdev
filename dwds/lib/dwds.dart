import 'dart:async';

import 'package:build_daemon/data/build_status.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:shelf/shelf.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'app_connection.dart';
import 'debug_connection.dart';
import 'src/devtools.dart';
import 'src/handlers/asset_handler.dart';
import 'src/handlers/dev_handler.dart';
import 'src/handlers/injected_handler.dart';

typedef LogWriter = void Function(Level, String);
typedef ConnectionProvider = Future<ChromeConnection> Function();
enum ReloadConfiguration { none, hotReload, hotRestart, liveReload }

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

  static Future<Dwds> start({
    @required String hostname,
    @required int applicationPort,
    @required int assetServerPort,
    @required String applicationTarget,
    @required ReloadConfiguration reloadConfiguration,
    @required Stream<BuildResult> buildResults,
    @required ConnectionProvider chromeConnection,
    @required bool serveDevTools,
    @required LogWriter logWriter,
    @required bool verbose,
  }) async {
    var assetHandler = AssetHandler(
      assetServerPort,
      applicationTarget,
      hostname,
      applicationPort,
    );
    var cascade = Cascade();
    var pipeline = const Pipeline();

    pipeline =
        pipeline.addMiddleware(createInjectedHandler(reloadConfiguration));

    DevTools devTools;
    if (serveDevTools) {
      devTools = await DevTools.start(hostname);
      logWriter(Level.INFO,
          'Serving DevTools at http://${devTools.hostname}:${devTools.port}\n');
    }
    var devHandler = DevHandler(
      chromeConnection,
      buildResults,
      devTools,
      assetHandler,
      hostname,
      verbose,
      logWriter,
    );
    cascade = cascade.add(devHandler.handler).add(assetHandler.handler);

    return Dwds._(pipeline.addHandler(cascade.handler), devTools, devHandler);
  }
}
