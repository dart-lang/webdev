// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../data/build_result.dart';
import '../../data/connect_request.dart';
import '../../data/debug_event.dart';
import '../../data/devtools_request.dart';
import '../../data/error_response.dart';
import '../../data/isolate_events.dart';
import '../../data/register_event.dart';
import '../../data/serializers.dart';
import '../../dwds.dart';
import '../debugging/execution_context.dart';
import '../debugging/remote_debugger.dart';
import '../debugging/webkit_debugger.dart';
import '../dwds_vm_client.dart';
import '../events.dart';
import '../servers/extension_backend.dart';
import '../services/app_debug_services.dart';
import '../services/debug_service.dart';
import 'injector.dart';

/// When enabled, this logs VM service protocol and Chrome debug protocol
/// traffic to disk.
///
/// Note: this should not be checked in enabled.
const _enableLogging = false;

final _logger = Logger('DevHandler');

/// SSE handler to enable development features like hot reload and
/// opening DevTools.
class DevHandler {
  final _subs = <StreamSubscription>[];
  final _sseHandlers = <String, SocketHandler>{};
  final _injectedConnections = <SocketConnection>{};
  final DevTools _devTools;
  final AssetReader _assetReader;
  final LoadStrategy _loadStrategy;
  final String _hostname;
  final _connectedApps = StreamController<AppConnection>.broadcast();
  final _servicesByAppId = <String, AppDebugServices>{};
  final _appConnectionByAppId = <String, AppConnection>{};
  final Stream<BuildResult> buildResults;
  final Future<ChromeConnection> Function() _chromeConnection;
  final ExtensionBackend _extensionBackend;
  final StreamController<DebugConnection> extensionDebugConnections =
      StreamController<DebugConnection>();
  final UrlEncoder _urlEncoder;
  final bool _useSseForDebugProxy;
  final bool _useSseForInjectedClient;
  final bool _serveDevTools;
  final bool _spawnDds;
  final bool _launchDevToolsInNewWindow;
  final ExpressionCompiler _expressionCompiler;
  final DwdsInjector _injected;
  final SdkConfigurationProvider _sdkConfigurationProvider;

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
    this._loadStrategy,
    this._hostname,
    this._extensionBackend,
    this._urlEncoder,
    this._useSseForDebugProxy,
    this._useSseForInjectedClient,
    this._serveDevTools,
    this._expressionCompiler,
    this._injected,
    this._spawnDds,
    this._launchDevToolsInNewWindow,
    this._sdkConfigurationProvider,
  ) {
    _subs.add(buildResults.listen(_emitBuildResults));
    _listen();
    if (_extensionBackend != null) {
      _listenForDebugExtension();
    }
  }

  Handler get handler => (request) async {
        var path = request.requestedUri.path;
        if (_sseHandlers.containsKey(path)) {
          return _sseHandlers[path].handler(request);
        }
        return Response.notFound('');
      };

  Future<void> close() => _closed ??= () async {
        for (var sub in _subs) {
          await sub.cancel();
        }
        for (var handler in _sseHandlers.values) {
          handler.shutdown();
        }
        await Future.wait(_servicesByAppId.values.map((service) async {
          await service.close();
        }));
        _servicesByAppId.clear();
      }();

  void _emitBuildResults(BuildResult result) {
    if (result.status != BuildStatus.succeeded) return;
    for (var injectedConnection in _injectedConnections) {
      injectedConnection.sink.add(jsonEncode(serializers.serialize(result)));
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
      if (tab.isChromeExtension || tab.isBackgroundPage) continue;

      tabConnection = await tab.connect();
      if (_enableLogging) {
        tabConnection.onSend.listen((message) {
          _log('  wip', '==> $message');
        });
        tabConnection.onReceive.listen((message) {
          _log('  wip', '<== $message');
        });
        tabConnection.onNotification.listen((message) {
          _log('  wip', '<== $message');
        });
      }
      var contextIds = tabConnection.runtime.onExecutionContextCreated
          .map((context) => context.id)
          // There is no way to calculate the number of existing execution
          // contexts so keep receiving them until there is a 50ms gap after
          // receiving the last one.
          .takeUntilGap(const Duration(milliseconds: 50));
      // We enqueue this work as we need to begin listening (`.hasNext`)
      // before events are received.
      unawaited(Future.microtask(() => tabConnection.runtime.enable()));

      await for (var contextId in contextIds) {
        var result = await tabConnection.sendCommand('Runtime.evaluate', {
          'expression': r'window["$dartAppInstanceId"];',
          'contextId': contextId,
        });
        var evaluatedAppId = result.result['result']['value'];
        if (evaluatedAppId == appInstanceId) {
          appTab = tab;
          executionContext = RemoteDebuggerExecutionContext(
              contextId, WebkitDebugger(WipDebugger(tabConnection)));
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
      _loadStrategy,
      appConnection,
      _urlEncoder,
      onResponse: (response) {
        if (response['error'] == null) return;
        _logger.finest('VmService proxy responded with an error:\n$response');
        if (_enableLogging) {
          _log('vm', '<== ${response.toString().replaceAll('\n', ' ')}');
        }
      },
      onRequest: (request) {
        if (_enableLogging) {
          _log('vm', '==> ${request.toString().replaceAll('\n', ' ')}');
        }
      },
      // This will provide a websocket based service.
      useSse: false,
      expressionCompiler: _expressionCompiler,
      spawnDds: _spawnDds,
      sdkConfigurationProvider: _sdkConfigurationProvider,
    );
  }

  void _log(String type, String message) {
    final logFile = File('${Platform.environment['HOME']}/dwds_log.txt');
    final time = (DateTime.now().millisecondsSinceEpoch % 1000000) / 1000.0;
    logFile.writeAsStringSync(
      '[${time.toStringAsFixed(3).padLeft(7)}s] $type $message\n',
      mode: FileMode.append,
    );
  }

  Future<AppDebugServices> loadAppServices(AppConnection appConnection) async {
    var appId = appConnection.request.appId;
    if (_servicesByAppId[appId] == null) {
      var debugService = await _startLocalDebugService(
          await _chromeConnection(), appConnection);
      var appServices = await _createAppDebugServices(
          appConnection.request.appId, debugService);
      unawaited(appServices.chromeProxyService.remoteDebugger.onClose.first
          .whenComplete(() async {
        await appServices.close();
        _servicesByAppId.remove(appConnection.request.appId);
        _logger.info('Stopped debug service on '
            'ws://${debugService.hostname}:${debugService.port}\n');
      }));
      _servicesByAppId[appId] = appServices;
    }
    return _servicesByAppId[appId];
  }

  void _handleConnection(SocketConnection injectedConnection) {
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
          } else if (message is BatchedDebugEvents) {
            await _servicesByAppId[appConnection.request.appId]
                ?.chromeProxyService
                ?.parseBatchedDebugEvents(message);
          } else if (message is DebugEvent) {
            await _servicesByAppId[appConnection.request.appId]
                ?.chromeProxyService
                ?.parseDebugEvent(message);
          } else if (message is RegisterEvent) {
            await _servicesByAppId[appConnection.request.appId]
                ?.chromeProxyService
                ?.parseRegisterEvent(message);
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
      AppConnection appConnection, SocketConnection sseConnection) async {
    if (_devTools == null) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..promptExtension = false
            ..error = 'Debugging is not enabled.\n\n'
                'If you are using webdev please pass the --debug flag.\n'
                'Otherwise check the docs for the tool you are using.'))));
      return;
    }
    var debuggerStart = DateTime.now();
    AppDebugServices appServices;
    try {
      appServices = await loadAppServices(appConnection);
    } catch (_) {
      var error = 'Unable to connect debug services to your '
          'application. Most likely this means you are trying to '
          'load in a different Chrome window than was launched by '
          'your development tool.';
      var response = DevToolsResponse((b) => b
        ..success = false
        ..promptExtension = false
        ..error = error);
      if (_extensionBackend != null) {
        response = response.rebuild((b) => b
          ..promptExtension = true
          ..error = '$error\n\n'
              'Your workflow alternatively supports debugging through the '
              'Dart Debug Extension.\n\n'
              'Would you like to install the extension?');
      }
      sseConnection.sink.add(jsonEncode(serializers.serialize(response)));
      return;
    }

    // Check if we are already running debug services for a different
    // instance of this app.
    if (appServices.connectedInstanceId != null &&
        appServices.connectedInstanceId != appConnection.request.instanceId) {
      sseConnection.sink
          .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
            ..success = false
            ..promptExtension = false
            ..error = 'This app is already being debugged in a different tab. '
                'Please close that tab or switch to it.'))));
      return;
    }

    sseConnection.sink
        .add(jsonEncode(serializers.serialize(DevToolsResponse((b) => b
          ..success = true
          ..promptExtension = false))));

    appServices.connectedInstanceId = appConnection.request.instanceId;
    appServices.dwdsStats.updateLoadTime(
      debuggerStart: debuggerStart,
      devToolsStart: DateTime.now(),
    );
    await _launchDevTools(appServices.chromeProxyService.remoteDebugger,
        _constructDevToolsUri(appServices.debugService.uri));
  }

  Future<AppConnection> _handleConnectRequest(
      ConnectRequest message, SocketConnection sseConnection) async {
    // After a page refresh, reconnect to the same app services if they
    // were previously launched and create the new isolate.
    var services = _servicesByAppId[message.appId];
    var existingAppConection = _appConnectionByAppId[message.appId];
    var connection = AppConnection(message, sseConnection);

    // We can take over a connection if there is no connectedInstanceId (this
    // means the client completely disconnected), or if the existing
    // AppConnection is in the KeepAlive state (this means it disconnected but
    // is still waiting for a possible reconnect - this happens during a page
    // reload).
    var canReuseConnection = services != null &&
        (services.connectedInstanceId == null ||
            existingAppConection?.isInKeepAlivePeriod == true);

    if (canReuseConnection) {
      // Disconnect any old connection (eg. those in the keep-alive waiting
      // state when reloading the page).
      existingAppConection?.shutDown();
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
      AppConnection appConnection, SocketConnection sseConnection) async {
    await _servicesByAppId[appConnection.request.appId]
        ?.chromeProxyService
        ?.createIsolate(appConnection);
  }

  void _listen() async {
    _subs.add(_injected.devHandlerPaths.listen((devHandlerPath) async {
      var uri = Uri.parse(devHandlerPath);
      if (!_sseHandlers.containsKey(uri.path)) {
        var handler = _useSseForInjectedClient
            ? SseSocketHandler(
                // We provide an essentially indefinite keep alive duration because
                // the underlying connection could be lost while the application
                // is paused. The connection will get re-established after a resume
                // or cleaned up on a full page refresh.
                SseHandler(uri, keepAlive: const Duration(days: 3000)))
            : WebSocketSocketHandler();
        _sseHandlers[uri.path] = handler;
        var injectedConnections = handler.connections;
        while (await injectedConnections.hasNext) {
          _handleConnection(await injectedConnections.next);
        }
      }
    }));
  }

  Future<AppDebugServices> _createAppDebugServices(
      String appId, DebugService debugService) async {
    var dwdsStats = DwdsStats();
    var webdevClient = await DwdsVmClient.create(debugService, dwdsStats);
    if (_spawnDds) {
      await debugService.startDartDevelopmentService();
    }
    var appDebugService =
        AppDebugServices(debugService, webdevClient, dwdsStats);
    var encodedUri = await debugService.encodedUri;
    _logger.info('Debug service listening on $encodedUri\n');
    await appDebugService.chromeProxyService.remoteDebugger
        .sendCommand('Runtime.evaluate', params: {
      'expression': 'console.log('
          '"This app is linked to the debug service: $encodedUri"'
          ');',
    });
    return appDebugService;
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
        _logger.warning(
            'Not connected to an app with id: ${devToolsRequest.appId}');
        return;
      }
      var debuggerStart = DateTime.now();
      var appId = devToolsRequest.appId;
      if (_servicesByAppId[appId] == null) {
        var debugService = await DebugService.start(
          _hostname,
          extensionDebugger,
          extensionDebugger.executionContext,
          devToolsRequest.tabUrl,
          _assetReader,
          _loadStrategy,
          connection,
          _urlEncoder,
          onResponse: (response) {
            if (response['error'] == null) return;
            _logger
                .finest('VmService proxy responded with an error:\n$response');
          },
          useSse: _useSseForDebugProxy,
          expressionCompiler: _expressionCompiler,
          spawnDds: _spawnDds,
          sdkConfigurationProvider: _sdkConfigurationProvider,
        );
        var appServices = await _createAppDebugServices(
          devToolsRequest.appId,
          debugService,
        );
        var encodedUri = await debugService.encodedUri;
        extensionDebugger.sendEvent('dwds.encodedUri', encodedUri);
        unawaited(appServices.chromeProxyService.remoteDebugger.onClose.first
            .whenComplete(() async {
          appServices.chromeProxyService.destroyIsolate();
          await appServices.close();
          _servicesByAppId.remove(devToolsRequest.appId);
          _logger.info('Stopped debug service on '
              '${await appServices.debugService.encodedUri}\n');
        }));
        extensionDebugConnections.add(DebugConnection(appServices));
        _servicesByAppId[appId] = appServices;
      }
      var appServices = _servicesByAppId[appId];
      final devToolsUri =
          _constructDevToolsUri(await appServices.debugService.encodedUri);

      // If we only want the URI, then return early.
      if (devToolsRequest.uriOnly != null && devToolsRequest.uriOnly) {
        extensionDebugger.sendEvent('dwds.devtoolsUri', devToolsUri);
        return;
      }
      appServices.dwdsStats.updateLoadTime(
        debuggerStart: debuggerStart,
        devToolsStart: DateTime.now(),
      );
      await _launchDevTools(extensionDebugger, devToolsUri);
    });
  }

  Future<void> _launchDevTools(
      RemoteDebugger remoteDebugger, String devToolsUri) async {
    // TODO(grouma) - We may want to log the debugServiceUri if we don't launch
    // DevTools so that users can manually connect.
    if (!_serveDevTools) return;
    emitEvent(DwdsEvent.devtoolsLaunch());
    await remoteDebugger.sendCommand('Target.createTarget', params: {
      'newWindow': _launchDevToolsInNewWindow,
      'url': devToolsUri,
    });
  }

  String _constructDevToolsUri(String debugServiceUri) {
    return Uri(
        scheme: 'http',
        host: _devTools.hostname,
        port: _devTools.port,
        queryParameters: {'uri': debugServiceUri}).toString();
  }
}

class AppConnectionException implements Exception {
  final String details;

  AppConnectionException(this.details);
}

extension<T> on Stream<T> {
  /// Forwards events from the original stream until a period of at least [gap]
  /// occurs in between events, in which case the returned stream will end.
  Stream<T> takeUntilGap(Duration gap) {
    final controller = isBroadcast
        ? StreamController<T>.broadcast(sync: true)
        : StreamController<T>(sync: true);

    StreamSubscription<T> subscription;
    Timer _gapTimer;
    controller.onListen = () {
      subscription = listen((e) {
        controller.add(e);
        _gapTimer?.cancel();
        _gapTimer = Timer(gap, () {
          subscription.cancel();
          controller.close();
        });
      }, onError: controller.addError, onDone: controller.close);
    };
    // Not handling pause/resume
    return controller.stream;
  }
}
