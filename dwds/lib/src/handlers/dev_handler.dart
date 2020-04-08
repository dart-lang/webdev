// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:dwds/data/build_result.dart';
import 'package:dwds/data/error_response.dart';
import 'package:dwds/data/run_request.dart';
import 'package:dwds/dwds.dart';
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/servers/extension_backend.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:logging/logging.dart';
import 'package:pedantic/pedantic.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../data/connect_request.dart';
import '../../data/devtools_request.dart';
import '../../data/isolate_events.dart';
import '../../data/serializers.dart';
import '../connections/app_connection.dart';
import '../dwds_vm_client.dart';
import '../readers/asset_reader.dart';
import '../servers/devtools.dart';
import '../services/app_debug_services.dart';
import '../services/debug_service.dart';

/// SSE handler to enable development features like hot reload and
/// opening DevTools.
class DevHandler {
  StreamSubscription _sub;
  final SseHandler _sseHandler = SseHandler(Uri.parse(r'/$sseHandler'),
      keepAlive: const Duration(seconds: 30));
  final _injectedConnections = <SseConnection>{};
  final DevTools _devTools;
  final AssetReader _assetReader;
  final String _hostname;
  final _connectedApps = StreamController<AppConnection>.broadcast();
  final _servicesByAppId = <String, AppDebugServices>{};
  final _appConnectionByAppId = <String, AppConnection>{};
  final Stream<BuildResult> buildResults;
  final bool _verbose;
  final void Function(Level, String) _logWriter;
  final Future<ChromeConnection> Function() _chromeConnection;
  final ExtensionBackend _extensionBackend;
  final StreamController<DebugConnection> extensionDebugConnections =
      StreamController<DebugConnection>();
  final UrlEncoder _urlEncoder;
  final bool _restoreBreakpoints;
  final bool _useSseForDebugProxy;
  final bool _serveDevTools;
  final ExpressionCompiler _expressionCompiler;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void> _closed;

  Stream<AppConnection> get connectedApps => _connectedApps.stream;

  DevHandler(
      this._chromeConnection,
      this.buildResults,
      this._devTools,
      this._assetReader,
      this._hostname,
      this._verbose,
      this._logWriter,
      this._extensionBackend,
      this._urlEncoder,
      this._restoreBreakpoints,
      this._useSseForDebugProxy,
      this._serveDevTools,
      this._expressionCompiler) {
    _sub = buildResults.listen(_emitBuildResults);
    _listen();
    if (_extensionBackend != null) {
      _listenForDebugExtension();
    }
  }

  Handler get handler => _sseHandler.handler;

  Future<void> close() => _closed ??= () async {
        await _sub.cancel();
        // We listen for connections to close and remove them from the connections
        // set. Therefore we shouldn't asynchronously iterate through the
        // connections.
        await Future.wait(_injectedConnections
            .map((injectedConnection) => injectedConnection.sink.close()));
        await Future.wait(_servicesByAppId.values.map((service) async {
          await service.close();
        }));
        _servicesByAppId.clear();
      }();

  void _emitBuildResults(BuildResult result) {
    if (result.status != BuildStatus.succeeded) return;
    for (var injectedConnection in _injectedConnections) {
      try {
        injectedConnection.sink.add(jsonEncode(serializers.serialize(result)));
      } on StateError catch (_) {
        // This will trigger clean up of the connection.
        injectedConnection.sink.close();
      }
    }
  }

  /// Starts a [DebugService] for local debugging.
  Future<DebugService> _startLocalDebugService(
      ChromeConnection chromeConnection, AppConnection appConnection) async {
    ChromeTab appTab;
    ExecutionContext executionContext;
    WipConnection tabConnection;
    var appInstanceId = appConnection.request.instanceId;
    for (var tab in await chromeConnection.getTabs()) {
      if (tab.url.startsWith('chrome-extensions:')) continue;
      tabConnection = await tab.connect();
      var contextQueue = StreamQueue<int>(tabConnection.runtime.eventStream(
          'Runtime.executionContextCreated',
          (e) => int.parse(e.params['context']['id'].toString())));
      // We enqueue this work as we need to begin listening (`.hasNext`)
      // before events are received.
      unawaited(Future.microtask(() => tabConnection.runtime.enable()));
      // There is no way to calculate the number of existing execution contexts
      // so we wait for a short while to receive a context.
      while (await contextQueue.hasNext
          .timeout(const Duration(milliseconds: 50), onTimeout: () => false)) {
        var context = await contextQueue.next;
        var result = await tabConnection.sendCommand('Runtime.evaluate', {
          'expression': r'window["$dartAppInstanceId"];',
          'contextId': context
        });
        var evaluatedAppId = result.result['result']['value'];
        if (evaluatedAppId == appInstanceId) {
          appTab = tab;
          executionContext = RemoteDebuggerExecutionContext(
              context, WebkitDebugger(WipDebugger(tabConnection)));
          break;
        }
      }
      if (appTab != null) break;
      unawaited(tabConnection.close());
    }
    if (appTab == null) {
      throw AppConnectionException(
          'Could not connect to application with appInstanceId: '
          '$appInstanceId');
    }

    var webkitDebugger = WebkitDebugger(WipDebugger(tabConnection));

    return DebugService.start(
        // We assume the user will connect to the debug service on the same
        // machine. This allows consumers of DWDS to provide a `hostname` for
        // debugging through the Dart Debug Extension without impacting the local
        // debug workflow.
        'localhost',
        webkitDebugger,
        executionContext,
        appTab.url,
        _assetReader,
        appConnection,
        _logWriter,
        _restoreBreakpoints,
        onResponse: _verbose
            ? (response) {
                if (response['error'] == null) return;
                _logWriter(Level.WARNING,
                    'VmService proxy responded with an error:\n$response');
              }
            : null,
        // This will provide a websocket based service.
        useSse: false,
        expressionCompiler: _expressionCompiler);
  }

  Future<AppDebugServices> loadAppServices(AppConnection appConnection) async {
    var appId = appConnection.request.appId;
    if (_servicesByAppId[appId] == null) {
      var debugService = await _startLocalDebugService(
          await _chromeConnection(), appConnection);
      var appServices = await _createAppDebugServices(
          appConnection.request.appId, debugService);
      unawaited(appServices.chromeProxyService.remoteDebugger.onClose.first
          .whenComplete(() {
        appServices.close();
        _servicesByAppId.remove(appConnection.request.appId);
        _logWriter(
            Level.INFO,
            'Stopped debug service on '
            'ws://${debugService.hostname}:${debugService.port}\n');
      }));
      _servicesByAppId[appId] = appServices;
    }
    return _servicesByAppId[appId];
  }

  void _handleConnection(SseConnection injectedConnection) {
    _injectedConnections.add(injectedConnection);
    AppConnection appConnection;
    injectedConnection.stream.listen((data) async {
      try {
        var message = serializers.deserialize(jsonDecode(data));
        if (message is ConnectRequest) {
          if (appConnection != null) {
            throw StateError('Duplicate connection request from the same app. '
                'Please file an issue at '
                'https://github.com/dart-lang/webdev/issues/new.');
          }
          appConnection =
              await _handleConnectRequest(message, injectedConnection);
        } else {
          if (appConnection == null) {
            throw StateError('Not connected to an application.');
          }
          if (message is DevToolsRequest) {
            await _handleDebugRequest(appConnection, injectedConnection);
          } else if (message is IsolateExit) {
            await _handleIsolateExit(appConnection);
          } else if (message is IsolateStart) {
            await _handleIsolateStart(appConnection, injectedConnection);
          }
        }
      } catch (e, s) {
        // Most likely the app disconnected in the middle of us responding,
        // but we will try and send an error response back to the page just in
        // case it is still running.
        try {
          injectedConnection.sink
              .add(jsonEncode(serializers.serialize(ErrorResponse((b) => b
                ..error = '$e'
                ..stackTrace = '$s'))));
        } on StateError catch (_) {
          // The sink has already closed (app is disconnected), swallow the
          // error.
        }
      }
    });

    unawaited(injectedConnection.sink.done.then((_) async {
      _injectedConnections.remove(injectedConnection);
      if (appConnection != null) {
        _appConnectionByAppId.remove(appConnection.request.appId);
        var services = _servicesByAppId[appConnection.request.appId];
        if (services != null) {
          if (services.connectedInstanceId == null ||
              services.connectedInstanceId ==
                  appConnection.request.instanceId) {
            services.connectedInstanceId = null;
            services.chromeProxyService?.destroyIsolate();
          }
        }
      }
    }));
  }

  Future<void> _handleDebugRequest(
      AppConnection appConnection, SseConnection sseConnection) async {
    if (_devTools == null) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..error = 'Debugging is not enabled.\n\n'
                'If you are using webdev please pass the --debug flag.\n'
                'Otherwise check the docs for the tool you are using.'))));
      return;
    }

    AppDebugServices appServices;
    try {
      appServices = await loadAppServices(appConnection);
    } catch (_) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..error = 'Unable to connect debug services to your '
                'application. Most likely this means you are trying to '
                'load in a different Chrome window than was launched by '
                'your development tool.'))));
      return;
    }

    // Check if we are already running debug services for a different
    // instance of this app.
    if (appServices.connectedInstanceId != null &&
        appServices.connectedInstanceId != appConnection.request.instanceId) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..error = 'This app is already being debugged in a different tab. '
                'Please close that tab or switch to it.'))));
      return;
    }

    sseConnection.sink.add(jsonEncode(
        serializers.serialize(DevToolsResponse((b) => b..success = true))));

    appServices.connectedInstanceId = appConnection.request.instanceId;
    await _launchDevTools(appServices.chromeProxyService.remoteDebugger,
        appServices.debugService.uri);
  }

  Future<AppConnection> _handleConnectRequest(
      ConnectRequest message, SseConnection sseConnection) async {
    // After a page refresh, reconnect to the same app services if they
    // were previously launched and create the new isolate.
    var services = _servicesByAppId[message.appId];
    var existingAppConection = _appConnectionByAppId[message.appId];
    var connection = AppConnection(message, sseConnection);

    // We can take over a connection if there is no connectedInstanceId (this means
    // the client completely disconnected), or if the existing AppConnection
    // is in the KeepAlive state (this means it disconnected but is still waiting
    // for a possible reconnect - this happens during a page reload).
    var canReuseConnection = services != null &&
        (services.connectedInstanceId == null ||
            existingAppConection?.isInKeepAlivePeriod == true);

    if (canReuseConnection) {
      // Disconnect any old connection (eg. those in the keep-alive waiting state
      // when reloading the page).
      services.chromeProxyService?.destroyIsolate();

      // Reconnect to existing service.
      services.connectedInstanceId = message.instanceId;
      await services.chromeProxyService.createIsolate(connection);
    }
    _appConnectionByAppId[message.appId] = connection;
    _connectedApps.add(connection);
    return connection;
  }

  Future<void> _handleIsolateExit(AppConnection appConnection) async {
    _servicesByAppId[appConnection.request.appId]
        ?.chromeProxyService
        ?.destroyIsolate();
  }

  Future<void> _handleIsolateStart(
      AppConnection appConnection, SseConnection sseConnection) async {
    await _servicesByAppId[appConnection.request.appId]
        ?.chromeProxyService
        ?.createIsolate(appConnection);
    // [IsolateStart] events are the result of a Hot Restart.
    // Run the application after the Isolate has been created.
    sseConnection.sink.add(jsonEncode(serializers.serialize(RunRequest())));
  }

  void _listen() async {
    var injectedConnections = _sseHandler.connections;
    while (await injectedConnections.hasNext) {
      _handleConnection(await injectedConnections.next);
    }
  }

  Future<AppDebugServices> _createAppDebugServices(
      String appId, DebugService debugService) async {
    _logWriter(
        Level.INFO,
        'Debug service listening on '
        '${debugService.uri}\n');
    var webdevClient = await DwdsVmClient.create(debugService);
    return AppDebugServices(debugService, webdevClient);
  }

  void _listenForDebugExtension() async {
    while (await _extensionBackend.connections.hasNext) {
      _startExtensionDebugService();
    }
  }

  /// Starts a [DebugService] for Dart Debug Extension.
  void _startExtensionDebugService() async {
    var extensionDebugger = await _extensionBackend.extensionDebugger;
    // Waits for a `DevToolsRequest` to be sent from the extension background
    // when the extension is clicked.
    extensionDebugger.devToolsRequestStream.listen((devToolsRequest) async {
      var connection = _appConnectionByAppId[devToolsRequest.appId];
      if (connection == null) {
        // TODO(grouma) - Ideally we surface this warning to the extension so
        // that it can be displayed to the user through an alert.
        _logWriter(Level.WARNING,
            'Not connected to an app with id: ${devToolsRequest.appId}');
        return;
      }
      var appId = devToolsRequest.appId;
      if (_servicesByAppId[appId] == null) {
        var debugService = await DebugService.start(
            _hostname,
            extensionDebugger,
            extensionDebugger.executionContext,
            devToolsRequest.tabUrl,
            _assetReader,
            connection,
            _logWriter,
            _restoreBreakpoints,
            onResponse: _verbose
                ? (response) {
                    if (response['error'] == null) return;
                    _logWriter(Level.WARNING,
                        'VmService proxy responded with an error:\n$response');
                  }
                : null,
            useSse: _useSseForDebugProxy,
            expressionCompiler: _expressionCompiler);
        var appServices =
            await _createAppDebugServices(devToolsRequest.appId, debugService);
        unawaited(appServices.chromeProxyService.remoteDebugger.onClose.first
            .whenComplete(() {
          appServices.chromeProxyService.destroyIsolate();
          appServices.close();
          _servicesByAppId.remove(devToolsRequest.appId);
          _logWriter(
              Level.INFO,
              'Stopped debug service on '
              '${appServices.debugService.uri}\n');
        }));
        extensionDebugConnections.add(DebugConnection(appServices));
        _servicesByAppId[appId] = appServices;
      }
      await _launchDevTools(
          extensionDebugger, _servicesByAppId[appId].debugService.uri);
    });
  }

  Future<void> _launchDevTools(
      RemoteDebugger remoteDebugger, String debugServiceUri) async {
    // TODO(grouma) - We may want to log the debugServiceUri if we don't launch
    // DevTools so that users can manually connect.
    if (!_serveDevTools) return;

    if (_urlEncoder != null) {
      debugServiceUri = await _urlEncoder(debugServiceUri);
    }
    await remoteDebugger.sendCommand('Target.createTarget', params: {
      'newWindow': true,
      'url': Uri(
          scheme: 'http',
          host: _devTools.hostname,
          port: _devTools.port,
          queryParameters: {'uri': debugServiceUri}).toString(),
    });
  }
}

class AppConnectionException implements Exception {
  final String details;
  AppConnectionException(this.details);
}
