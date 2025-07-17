// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/data/build_result.dart';
import 'package:dwds/data/connect_request.dart';
import 'package:dwds/data/debug_event.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/error_response.dart';
import 'package:dwds/data/hot_reload_response.dart';
import 'package:dwds/data/isolate_events.dart';
import 'package:dwds/data/register_event.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/data/service_extension_response.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/connections/debug_connection.dart';
import 'package:dwds/src/debugging/execution_context.dart';
import 'package:dwds/src/debugging/remote_debugger.dart';
import 'package:dwds/src/debugging/webkit_debugger.dart';
import 'package:dwds/src/dwds_vm_client.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/handlers/injector.dart';
import 'package:dwds/src/handlers/socket_connections.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:dwds/src/servers/devtools.dart';
import 'package:dwds/src/servers/extension_backend.dart';
import 'package:dwds/src/servers/extension_debugger.dart';
import 'package:dwds/src/services/app_debug_services.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/services/expression_compiler.dart';
import 'package:dwds/src/services/web_socket_app_debug_services.dart';
import 'package:dwds/src/services/web_socket_debug_service.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:dwds/src/web_socket_dwds_vm_client.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:sse/server/sse_handler.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

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
  final DevTools? _devTools;
  final AssetReader _assetReader;
  final String _hostname;
  final _connectedApps = StreamController<AppConnection>.broadcast();
  final _servicesByAppId = <String, IAppDebugServices>{};
  final _appConnectionByAppId = <String, AppConnection>{};
  final Stream<BuildResult> buildResults;
  final Future<ChromeConnection> Function() _chromeConnection;
  final ExtensionBackend? _extensionBackend;
  final StreamController<DebugConnection> extensionDebugConnections =
      StreamController<DebugConnection>();
  final UrlEncoder? _urlEncoder;
  final bool _useSseForDebugProxy;
  final bool _useSseForInjectedClient;
  final bool _spawnDds;
  final int? _ddsPort;
  final bool _launchDevToolsInNewWindow;
  final ExpressionCompiler? _expressionCompiler;
  final DwdsInjector _injected;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  Stream<AppConnection> get connectedApps => _connectedApps.stream;

  final bool useWebSocketConnection;

  DevHandler(
    this._chromeConnection,
    this.buildResults,
    this._devTools,
    this._assetReader,
    this._hostname,
    this._extensionBackend,
    this._urlEncoder,
    this._useSseForDebugProxy,
    this._useSseForInjectedClient,
    this._expressionCompiler,
    this._injected,
    this._spawnDds,
    this._ddsPort,
    this._launchDevToolsInNewWindow, {
    this.useWebSocketConnection = false,
  }) {
    _subs.add(buildResults.listen(_emitBuildResults));
    _listen();
    if (_extensionBackend != null) {
      _listenForDebugExtension();
    }
  }

  Handler get handler => (request) async {
    final path = request.requestedUri.path;
    final sseHandler = _sseHandlers[path];
    if (sseHandler != null) {
      return sseHandler.handler(request);
    }
    return Response.notFound('');
  };

  Future<void> close() =>
      _closed ??= () async {
        for (final sub in _subs) {
          await sub.cancel();
        }
        for (final handler in _sseHandlers.values) {
          handler.shutdown();
        }
        await Future.wait(
          _servicesByAppId.values.map((service) => service.close()),
        );
        _servicesByAppId.clear();
      }();

  void _emitBuildResults(BuildResult result) {
    if (result.status != BuildStatus.succeeded) return;
    for (final injectedConnection in _injectedConnections) {
      injectedConnection.sink.add(jsonEncode(serializers.serialize(result)));
    }
  }

  /// Sends the provided [request] to all connected injected clients.
  /// Returns the number of clients the request was successfully sent to.
  int _sendRequestToClients(Object request) {
    var successfulSends = 0;
    for (final injectedConnection in _injectedConnections) {
      try {
        injectedConnection.sink.add(jsonEncode(serializers.serialize(request)));
        successfulSends++;
      } on StateError catch (e) {
        // The sink has already closed (app is disconnected), or another StateError occurred.
        _logger.warning(
          'Failed to send request to client ${injectedConnection.hashCode}, '
          'connection likely closed. Error: $e',
        );
      } catch (e, s) {
        // Catch any other potential errors during sending.
        _logger.severe(
          'Error sending request to client ${injectedConnection.hashCode}: $e',
          e,
          s,
        );
      }
    }
    return successfulSends;
  }

  /// Starts a [DebugService] for local debugging.
  Future<DebugService> _startLocalDebugService(
    ChromeConnection chromeConnection,
    AppConnection appConnection,
  ) async {
    ChromeTab? appTab;
    ExecutionContext? executionContext;
    WipConnection? tabConnection;
    final appInstanceId = appConnection.request.instanceId;
    for (final tab in await chromeConnection.getTabs()) {
      if (tab.isChromeExtension || tab.isBackgroundPage) continue;

      final connection = tabConnection = await tab.connect();
      if (_enableLogging) {
        connection.onSend.listen((message) {
          _log('  wip', '==> $message');
        });
        connection.onReceive.listen((message) {
          _log('  wip', '<== $message');
        });
        connection.onNotification.listen((message) {
          _log('  wip', '<== $message');
        });
      }
      final contextIds = connection.runtime.onExecutionContextCreated
          .map((context) => context.id)
          // There is no way to calculate the number of existing execution
          // contexts so keep receiving them until there is a 50ms gap after
          // receiving the last one.
          .takeUntilGap(const Duration(milliseconds: 50));
      // We enqueue this work as we need to begin listening (`.hasNext`)
      // before events are received.
      safeUnawaited(Future.microtask(connection.runtime.enable));

      await for (final contextId in contextIds) {
        final result = await connection.sendCommand('Runtime.evaluate', {
          'expression': r'window["$dartAppInstanceId"];',
          'contextId': contextId,
        });
        final evaluatedAppId = result.result?['result']?['value'];
        if (evaluatedAppId == appInstanceId) {
          appTab = tab;
          executionContext = RemoteDebuggerExecutionContext(
            contextId,
            WebkitDebugger(WipDebugger(connection)),
          );
          break;
        }
      }
      if (appTab != null) break;
      safeUnawaited(connection.close());
    }
    if (appTab == null || tabConnection == null || executionContext == null) {
      throw AppConnectionException(
        'Could not connect to application with appInstanceId: '
        '$appInstanceId',
      );
    }

    final webkitDebugger = WebkitDebugger(WipDebugger(tabConnection));

    return DebugService.start(
      // We assume the user will connect to the debug service on the same
      // machine. This allows consumers of DWDS to provide a `hostname` for
      // debugging through the Dart Debug Extension without impacting the local
      // debug workflow.
      'localhost',
      webkitDebugger,
      executionContext,
      _assetReader,
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
      ddsPort: _ddsPort,
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

  Future<IAppDebugServices> loadAppServices(AppConnection appConnection) async {
    final appId = appConnection.request.appId;
    var appServices = _servicesByAppId[appId];
    if (appServices == null) {
      if (useWebSocketConnection) {
        appServices = await _createWebSocketAppServices(appConnection);
      } else {
        appServices = await _createChromeAppServices(appConnection);
        _setupChromeServiceCleanup(appServices, appConnection);
      }
      _servicesByAppId[appId] = appServices;
    }

    return appServices;
  }

  /// Creates WebSocket-based app services for hot reload functionality.
  Future<IAppDebugServices> _createWebSocketAppServices(
    AppConnection appConnection,
  ) async {
    final webSocketDebugService = await WebSocketDebugService.start(
      'localhost',
      appConnection,
      sendClientRequest: _sendRequestToClients,
    );
    return _createAppDebugServicesWebSocketMode(
      webSocketDebugService,
      appConnection,
    );
  }

  /// Creates Chrome-based app services for full debugging capabilities.
  Future<IAppDebugServices> _createChromeAppServices(
    AppConnection appConnection,
  ) async {
    final debugService = await _startLocalDebugService(
      await _chromeConnection(),
      appConnection,
    );
    return _createAppDebugServices(debugService);
  }

  /// Sets up cleanup handling for Chrome-based services.
  void _setupChromeServiceCleanup(
    IAppDebugServices appServices,
    AppConnection appConnection,
  ) {
    safeUnawaited(
      appServices.chromeProxyService.remoteDebugger.onClose.first.whenComplete(
        () async {
          await appServices.close();
          _servicesByAppId.remove(appConnection.request.appId);
          _logger.info(
            'Stopped debug service on '
            'ws://${appServices.debugService.hostname}:${appServices.debugService.port}\n',
          );
        },
      ),
    );
  }

  void _handleConnection(SocketConnection injectedConnection) {
    _injectedConnections.add(injectedConnection);
    AppConnection? appConnection;
    injectedConnection.stream.listen((data) async {
      try {
        final message = serializers.deserialize(jsonDecode(data));
        if (message is ConnectRequest) {
          if (appConnection != null) {
            throw StateError(
              'Duplicate connection request from the same app. '
              'Please file an issue at '
              'https://github.com/dart-lang/webdev/issues/new.',
            );
          }
          appConnection =
              useWebSocketConnection
                  ? await _handleWebSocketConnectRequest(
                    message,
                    injectedConnection,
                  )
                  : await _handleConnectRequest(message, injectedConnection);
        } else {
          final connection = appConnection;
          if (connection == null) {
            throw StateError('Not connected to an application.');
          }
          if (message is DevToolsRequest) {
            await _handleDebugRequest(connection, injectedConnection);
          } else if (useWebSocketConnection) {
            // Handle WebSocket-specific messages
            await _handleWebSocketMessage(connection, message);
          } else {
            // Handle Chrome-specific messages
            await _handleChromeMessage(connection, message);
          }
        }
      } catch (e, s) {
        // Most likely the app disconnected in the middle of us responding,
        // but we will try and send an error response back to the page just in
        // case it is still running.
        try {
          injectedConnection.sink.add(
            jsonEncode(
              serializers.serialize(
                ErrorResponse(
                  (b) =>
                      b
                        ..error = '$e'
                        ..stackTrace = '$s',
                ),
              ),
            ),
          );
        } on StateError catch (_) {
          // The sink has already closed (app is disconnected), swallow the
          // error.
        }
      }
    });

    safeUnawaited(
      injectedConnection.sink.done.then((_) {
        _injectedConnections.remove(injectedConnection);
        final connection = appConnection;
        if (connection != null) {
          _appConnectionByAppId.remove(connection.request.appId);
          final services = _servicesByAppId[connection.request.appId];
          if (services != null) {
            if (services.connectedInstanceId == null ||
                services.connectedInstanceId == connection.request.instanceId) {
              services.connectedInstanceId = null;
              _handleIsolateExit(connection);
            }
          }
        }
      }),
    );
  }

  /// Handles WebSocket-specific messages.
  Future<void> _handleWebSocketMessage(
    AppConnection connection,
    Object? message,
  ) async {
    if (message == null) return;

    final appId = connection.request.appId;
    final wsService = _servicesByAppId[appId]?.webSocketProxyService;

    if (wsService == null) {
      _logger.warning(
        'No WebSocketProxyService found for appId: $appId to process $message',
      );
      return;
    }
    if (message is HotReloadResponse) {
      wsService.completeHotReload(message);
    } else if (message is ServiceExtensionResponse) {
      wsService.completeServiceExtension(message);
    } else if (message is RegisterEvent) {
      wsService.parseRegisterEvent(message);
    } else if (message is BatchedDebugEvents) {
      wsService.parseBatchedDebugEvents(message);
    } else if (message is DebugEvent) {
      wsService.parseDebugEvent(message);
    } else {
      throw UnsupportedError(
        'Message type ${message.runtimeType} is not supported in WebSocket mode',
      );
    }
  }

  /// Handles Chrome-specific messages.
  Future<void> _handleChromeMessage(
    AppConnection connection,
    Object? message,
  ) async {
    if (message == null) return;

    if (message is HotReloadResponse) {
      _servicesByAppId[connection.request.appId]?.chromeProxyService
          .completeHotReload(message);
    } else if (message is IsolateExit) {
      _handleIsolateExit(connection);
    } else if (message is IsolateStart) {
      await _handleIsolateStart(connection);
    } else if (message is BatchedDebugEvents) {
      _servicesByAppId[connection.request.appId]?.chromeProxyService
          .parseBatchedDebugEvents(message);
    } else if (message is DebugEvent) {
      _servicesByAppId[connection.request.appId]?.chromeProxyService
          .parseDebugEvent(message);
    } else if (message is RegisterEvent) {
      _servicesByAppId[connection.request.appId]?.chromeProxyService
          .parseRegisterEvent(message);
    } else {
      throw UnsupportedError(
        'Message type ${message.runtimeType} is not supported in Chrome mode',
      );
    }
  }

  Future<void> _handleDebugRequest(
    AppConnection appConnection,
    SocketConnection sseConnection,
  ) async {
    if (_devTools == null) {
      sseConnection.sink.add(
        jsonEncode(
          serializers.serialize(
            DevToolsResponse(
              (b) =>
                  b
                    ..success = false
                    ..promptExtension = false
                    ..error =
                        'Debugging is not enabled.\n\n'
                        'If you are using webdev please pass the --debug flag.\n'
                        'Otherwise check the docs for the tool you are using.',
            ),
          ),
        ),
      );
      return;
    }
    final debuggerStart = DateTime.now();
    IAppDebugServices appServices;
    try {
      appServices = await loadAppServices(appConnection);
    } catch (_) {
      final error =
          'Unable to connect debug services to your '
          'application. Most likely this means you are trying to '
          'load in a different Chrome window than was launched by '
          'your development tool.';
      var response = DevToolsResponse(
        (b) =>
            b
              ..success = false
              ..promptExtension = false
              ..error = error,
      );
      if (_extensionBackend != null) {
        response = response.rebuild(
          (b) =>
              b
                ..promptExtension = true
                ..error =
                    '$error\n\n'
                    'Your workflow alternatively supports debugging through the '
                    'Dart Debug Extension.\n\n'
                    'Would you like to install the extension?',
        );
      }
      sseConnection.sink.add(jsonEncode(serializers.serialize(response)));
      return;
    }

    // Check if we are already running debug services for a different
    // instance of this app.
    if (appServices.connectedInstanceId != null &&
        appServices.connectedInstanceId != appConnection.request.instanceId) {
      sseConnection.sink.add(
        jsonEncode(
          serializers.serialize(
            DevToolsResponse(
              (b) =>
                  b
                    ..success = false
                    ..promptExtension = false
                    ..error =
                        'This app is already being debugged in a different tab. '
                        'Please close that tab or switch to it.',
            ),
          ),
        ),
      );
      return;
    }

    sseConnection.sink.add(
      jsonEncode(
        serializers.serialize(
          DevToolsResponse(
            (b) =>
                b
                  ..success = true
                  ..promptExtension = false,
          ),
        ),
      ),
    );

    appServices.connectedInstanceId = appConnection.request.instanceId;
    appServices.dwdsStats.updateLoadTime(
      debuggerStart: debuggerStart,
      devToolsStart: DateTime.now(),
    );
    await _launchDevTools(
      appServices.chromeProxyService.remoteDebugger,
      _constructDevToolsUri(
        appServices.debugService.uri,
        ideQueryParam: 'Dwds',
      ),
    );
  }

  /// Creates a debug connection for WebSocket mode.
  Future<DebugConnection> createDebugConnectionForWebSocket(
    AppConnection appConnection,
  ) async {
    final appDebugServices = await loadAppServices(appConnection);

    // Initialize WebSocket proxy service
    final webSocketProxyService = appDebugServices.webSocketProxyService;
    if (webSocketProxyService != null) {
      await webSocketProxyService.isInitialized;
      _logger.fine('WebSocket proxy service initialized successfully');
    } else {
      _logger.warning('WebSocket proxy service is null');
    }

    return DebugConnection(appDebugServices);
  }

  /// Creates a debug connection for Chrome mode.
  Future<DebugConnection> createDebugConnectionForChrome(
    AppConnection appConnection,
  ) async {
    final appDebugServices = await loadAppServices(appConnection);

    // Initialize Chrome proxy service
    try {
      final chromeProxyService = appDebugServices.chromeProxyService;
      if (chromeProxyService != null) {
        await chromeProxyService.isInitialized;
        _logger.fine('Chrome proxy service initialized successfully');
      } else {
        _logger.warning('Chrome proxy service is null');
      }
    } catch (e) {
      _logger.severe('Failed to initialize Chrome proxy service: $e');
      rethrow;
    }

    return DebugConnection(appDebugServices);
  }

  Future<AppConnection> _handleConnectRequest(
    ConnectRequest message,
    SocketConnection sseConnection,
  ) async {
    // After a page refresh, reconnect to the same app services if they
    // were previously launched and create the new isolate.
    final services = _servicesByAppId[message.appId];
    final existingConnection = _appConnectionByAppId[message.appId];
    // Completer to indicate when the app's main() method is ready to be run.
    // Its future is passed to the AppConnection so that it can be awaited on
    // before running the app's main() method:
    final readyToRunMainCompleter = Completer<void>();
    final connection = AppConnection(
      message,
      sseConnection,
      readyToRunMainCompleter.future,
    );

    // We can take over a connection if there is no connectedInstanceId (this
    // means the client completely disconnected), or if the existing
    // AppConnection is in the KeepAlive state (this means it disconnected but
    // is still waiting for a possible reconnect - this happens during a page
    // reload).
    final canReuseConnection =
        services != null &&
        (services.connectedInstanceId == null ||
            existingConnection?.isInKeepAlivePeriod == true);

    if (canReuseConnection) {
      // Disconnect any old connection (eg. those in the keep-alive waiting
      // state when reloading the page).
      existingConnection?.shutDown();
      services.chromeProxyService.destroyIsolate();

      // Reconnect to existing service.
      services.connectedInstanceId = message.instanceId;

      if (services.chromeProxyService.pauseIsolatesOnStart) {
        // If the pause-isolates-on-start flag is set, we need to wait for
        // the resume event to run the app's main() method.
        _waitForResumeEventToRunMain(
          services.chromeProxyService.resumeAfterRestartEventsStream,
          readyToRunMainCompleter,
        );
      } else {
        // Otherwise, we can run the app's main() method immediately.
        readyToRunMainCompleter.complete();
      }

      await services.chromeProxyService.createIsolate(connection);
    } else {
      // If this is the initial app connection, we can run the app's main()
      // method immediately.
      readyToRunMainCompleter.complete();
    }
    _appConnectionByAppId[message.appId] = connection;
    _connectedApps.add(connection);
    return connection;
  }

  /// Handles WebSocket mode connection requests with multi-window support.
  Future<AppConnection> _handleWebSocketConnectRequest(
    ConnectRequest message,
    SocketConnection sseConnection,
  ) async {
    // After a page refresh, reconnect to the same app services if they
    // were previously launched and create the new isolate.
    final services = _servicesByAppId[message.appId];
    final existingConnection = _appConnectionByAppId[message.appId];
    // Completer to indicate when the app's main() method is ready to be run.
    // Its future is passed to the AppConnection so that it can be awaited on
    // before running the app's main() method:
    final readyToRunMainCompleter = Completer<void>();
    final connection = AppConnection(
      message,
      sseConnection,
      readyToRunMainCompleter.future,
    );

    // Allow connection reuse for page refreshes and same instance reconnections
    final isSameInstance =
        existingConnection?.request.instanceId == message.instanceId;
    final isKeepAliveReconnect =
        existingConnection?.isInKeepAlivePeriod == true;
    final hasNoActiveConnection = services?.connectedInstanceId == null;
    final noExistingConnection = existingConnection == null;

    final canReuseConnection =
        services != null &&
        (isSameInstance ||
            (isKeepAliveReconnect && hasNoActiveConnection) ||
            (noExistingConnection && hasNoActiveConnection));

    if (canReuseConnection) {
      // Reconnect to existing service.
      await _reconnectToService(
        services,
        existingConnection,
        connection,
        message,
        readyToRunMainCompleter,
      );
    } else {
      // New browser window or initial connection: run main() immediately
      readyToRunMainCompleter.complete();

      // For WebSocket mode, we need to proactively create and emit a debug connection
      // since Flutter tools won't call debugConnection() for WebServerDevice
      try {
        // Initialize the WebSocket service and create debug connection
        final debugConnection = await createDebugConnectionForWebSocket(
          connection,
        );

        // Emit the debug connection through the extension stream
        // This should trigger Flutter tools to pick it up as if it was an extension connection
        extensionDebugConnections.add(debugConnection);
      } catch (e, s) {
        _logger.warning('Failed to create WebSocket debug connection: $e\n$s');
      }
    }
    _appConnectionByAppId[message.appId] = connection;
    _connectedApps.add(connection);
    _logger.fine('App connection established for: ${message.appId}');
    return connection;
  }

  /// Handles reconnection to existing services for web-socket mode.
  Future<void> _reconnectToService(
    IAppDebugServices services,
    AppConnection? existingConnection,
    AppConnection newConnection,
    ConnectRequest message,
    Completer<void> readyToRunMainCompleter,
  ) async {
    // Disconnect old connection
    existingConnection?.shutDown();
    services.connectedInstanceId = message.instanceId;

    services.webSocketProxyService?.destroyIsolate();
    _logger.finest('WebSocket service reconnected for app: ${message.appId}');

    _setupMainExecution(
      services.webSocketProxyService?.pauseIsolatesOnStart == true,
      services.webSocketProxyService?.resumeAfterRestartEventsStream,
      readyToRunMainCompleter,
    );

    await _handleIsolateStart(newConnection);
  }

  /// Sets up main() execution timing based on pause settings.
  void _setupMainExecution(
    bool pauseIsolatesOnStart,
    Stream<String>? resumeEventsStream,
    Completer<void> readyToRunMainCompleter,
  ) {
    if (pauseIsolatesOnStart && resumeEventsStream != null) {
      _waitForResumeEventToRunMain(resumeEventsStream, readyToRunMainCompleter);
    } else {
      readyToRunMainCompleter.complete();
    }
  }

  /// Waits for a resume event to trigger the app's main() method.
  ///
  /// The [readyToRunMainCompleter]'s future will be passed to the
  /// [AppConnection] so that it can be awaited on before running the app's
  /// main() method.
  void _waitForResumeEventToRunMain(
    Stream<String> resumeEventsStream,
    Completer<void> readyToRunMainCompleter,
  ) {
    StreamSubscription<String>? resumeEventsSubscription;
    resumeEventsSubscription = resumeEventsStream.listen((_) async {
      await resumeEventsSubscription!.cancel();
      readyToRunMainCompleter.complete();
    });
  }

  /// Handles isolate exit events for both WebSocket and Chrome-based debugging.
  void _handleIsolateExit(AppConnection appConnection) {
    final appId = appConnection.request.appId;

    if (useWebSocketConnection) {
      _servicesByAppId[appId]?.webSocketProxyService?.destroyIsolate();
    } else {
      _servicesByAppId[appId]?.chromeProxyService.destroyIsolate();
    }
  }

  /// Handles isolate start events for both WebSocket and Chrome-based debugging.
  Future<void> _handleIsolateStart(AppConnection appConnection) async {
    final appId = appConnection.request.appId;

    if (useWebSocketConnection) {
      await _servicesByAppId[appId]?.webSocketProxyService?.createIsolate(
        appConnection,
      );
    } else {
      await _servicesByAppId[appId]?.chromeProxyService.createIsolate(
        appConnection,
      );
    }
  }

  void _listen() {
    _subs.add(
      _injected.devHandlerPaths.listen((devHandlerPath) async {
        final uri = Uri.parse(devHandlerPath);
        if (!_sseHandlers.containsKey(uri.path)) {
          final handler =
              _useSseForInjectedClient
                  ? SseSocketHandler(
                    // We provide an essentially indefinite keep alive duration because
                    // the underlying connection could be lost while the application
                    // is paused. The connection will get re-established after a resume
                    // or cleaned up on a full page refresh.
                    SseHandler(uri, keepAlive: const Duration(days: 3000)),
                  )
                  : WebSocketSocketHandler();
          _sseHandlers[uri.path] = handler;
          final injectedConnections = handler.connections;
          while (await injectedConnections.hasNext) {
            _handleConnection(await injectedConnections.next);
          }
        }
      }),
    );
  }

  Future<IAppDebugServices> _createAppDebugServices(
    DebugService debugService,
  ) async {
    final dwdsStats = DwdsStats();
    Uri? ddsUri;
    if (_spawnDds) {
      final dds = await debugService.startDartDevelopmentService();
      ddsUri = dds.wsUri;
    }
    final vmClient = await DwdsVmClient.create(debugService, dwdsStats, ddsUri);
    final appDebugService = AppDebugServices(
      debugService,
      vmClient,
      dwdsStats,
      ddsUri,
    );
    final encodedUri = await debugService.encodedUri;
    _logger.info('Debug service listening on $encodedUri\n');
    await appDebugService.chromeProxyService.remoteDebugger.sendCommand(
      'Runtime.evaluate',
      params: {
        'expression':
            'console.log('
            '"This app is linked to the debug service: $encodedUri"'
            ');',
      },
    );

    // Notify that DWDS has been launched and a debug connection has been made:
    _maybeEmitDwdsLaunchEvent();

    return appDebugService;
  }

  Future<IAppDebugServices> _createAppDebugServicesWebSocketMode(
    WebSocketDebugService webSocketDebugService,
    AppConnection appConnection,
  ) async {
    final wsVmClient = await WebSocketDwdsVmClient.create(
      webSocketDebugService,
    );
    final wsAppDebugService = WebSocketAppDebugServices(
      webSocketDebugService,
      wsVmClient,
    );

    safeUnawaited(_handleIsolateStart(appConnection));
    final debugServiceUri = webSocketDebugService.uri;
    _logger.info('Debug service listening on $debugServiceUri\n');

    // Notify that DWDS has been launched and a debug connection has been made:
    _maybeEmitDwdsLaunchEvent();

    return wsAppDebugService;
  }

  Future<void> _listenForDebugExtension() async {
    final extensionBackend = _extensionBackend;
    if (extensionBackend == null) {
      _logger.severe('No debug extension backend. Debugging will not work.');
      return;
    }

    while (await extensionBackend.connections.hasNext) {
      final extensionDebugger = await extensionBackend.extensionDebugger;
      _startExtensionDebugService(extensionDebugger);
    }
  }

  /// Starts a [DebugService] for Dart Debug Extension.
  void _startExtensionDebugService(ExtensionDebugger extensionDebugger) {
    // Waits for a `DevToolsRequest` to be sent from the extension background
    // when the extension is clicked.
    extensionDebugger.devToolsRequestStream.listen((devToolsRequest) async {
      try {
        await _handleDevToolsRequest(extensionDebugger, devToolsRequest);
        _logger.finest('DevTools request processed successfully');
      } catch (error) {
        _logger.severe('Encountered error handling DevTools request.');
        extensionDebugger.closeWithError(error);
      }
    });
  }

  Future<void> _handleDevToolsRequest(
    ExtensionDebugger extensionDebugger,
    DevToolsRequest devToolsRequest,
  ) async {
    // TODO(grouma) - Ideally we surface those warnings to the extension so
    // that it can be displayed to the user through an alert.
    final tabUrl = devToolsRequest.tabUrl;
    final appId = devToolsRequest.appId;
    if (tabUrl == null) {
      throw StateError(
        'Failed to start extension debug service. '
        'Missing tab url in DevTools request for app with id: $appId',
      );
    }
    final connection = _appConnectionByAppId[appId];
    if (connection == null) {
      throw StateError(
        'Failed to start extension debug service. '
        'Not connected to an app with id: $appId',
      );
    }
    final executionContext = extensionDebugger.executionContext;
    if (executionContext == null) {
      throw StateError(
        'Failed to start extension debug service. '
        'No execution context for app with id: $appId',
      );
    }

    final debuggerStart = DateTime.now();
    var appServices = _servicesByAppId[appId];
    if (appServices == null) {
      final debugService = await DebugService.start(
        _hostname,
        extensionDebugger,
        executionContext,
        _assetReader,
        connection,
        _urlEncoder,
        onResponse: (response) {
          if (response['error'] == null) return;
          _logger.finest('VmService proxy responded with an error:\n$response');
        },
        useSse: _useSseForDebugProxy,
        expressionCompiler: _expressionCompiler,
        spawnDds: _spawnDds,
        ddsPort: _ddsPort,
      );
      appServices = await _createAppDebugServices(debugService);
      extensionDebugger.sendEvent('dwds.debugUri', debugService.uri);
      final encodedUri = await debugService.encodedUri;
      extensionDebugger.sendEvent('dwds.encodedUri', encodedUri);
      safeUnawaited(
        appServices.chromeProxyService.remoteDebugger.onClose.first
            .whenComplete(() async {
              appServices?.chromeProxyService.destroyIsolate();
              await appServices?.close();
              _servicesByAppId.remove(devToolsRequest.appId);
              _logger.info(
                'Stopped debug service on '
                '${await appServices?.debugService.encodedUri}\n',
              );
            }),
      );
      extensionDebugConnections.add(DebugConnection(appServices));
      _servicesByAppId[appId] = appServices;
    }

    _maybeEmitDwdsAttachEvent(devToolsRequest);

    // If we don't have a DevTools instance, then are connecting to an IDE.
    // Therefore return early instead of opening DevTools:
    if (_devTools == null) return;

    final encodedUri = await appServices.debugService.encodedUri;

    appServices.dwdsStats.updateLoadTime(
      debuggerStart: debuggerStart,
      devToolsStart: DateTime.now(),
    );

    emitEvent(DwdsEvent.devtoolsLaunch());
    // Send the DevTools URI to the Dart Debug Extension so that it can open it:
    final devToolsUri = _constructDevToolsUri(
      encodedUri,
      ideQueryParam: 'ChromeDevTools',
    );
    return extensionDebugger.sendEvent('dwds.devtoolsUri', devToolsUri);
  }

  DevTools _ensureDevTools() {
    final devTools = _devTools;
    if (devTools == null) {
      throw StateError('DevHandler: DevTools is not available');
    }
    return devTools;
  }

  Future<void> _launchDevTools(
    RemoteDebugger remoteDebugger,
    String devToolsUri,
  ) async {
    // TODO(annagrin): move checking whether devtools should be started
    // and the creation of the uri logic here so it is easier to follow.
    _ensureDevTools();
    // TODO(grouma) - We may want to log the debugServiceUri if we don't launch
    // DevTools so that users can manually connect.
    emitEvent(DwdsEvent.devtoolsLaunch());
    await remoteDebugger.sendCommand(
      'Target.createTarget',
      params: {'newWindow': _launchDevToolsInNewWindow, 'url': devToolsUri},
    );
  }

  String _constructDevToolsUri(
    String debugServiceUri, {
    String ideQueryParam = '',
  }) {
    final devTools = _ensureDevTools();
    return Uri(
      scheme: 'http',
      host: devTools.hostname,
      port: devTools.port,
      path: 'debugger',
      queryParameters: {
        'uri': debugServiceUri,
        if (ideQueryParam.isNotEmpty) 'ide': ideQueryParam,
      },
    ).toString();
  }

  static void _maybeEmitDwdsAttachEvent(DevToolsRequest request) {
    if (request.client != null) {
      emitEvent(
        DwdsEvent.dwdsAttach(
          client: request.client!,
          isFlutterApp:
              globalToolConfiguration.loadStrategy.buildSettings.isFlutterApp,
        ),
      );
    }
  }

  static void _maybeEmitDwdsLaunchEvent() {
    if (globalToolConfiguration.appMetadata.codeRunner != null) {
      emitEvent(
        DwdsEvent.dwdsLaunch(
          codeRunner: globalToolConfiguration.appMetadata.codeRunner!,
          isFlutterApp:
              globalToolConfiguration.loadStrategy.buildSettings.isFlutterApp,
        ),
      );
    }
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
    final controller =
        isBroadcast
            ? StreamController<T>.broadcast(sync: true)
            : StreamController<T>(sync: true);

    late StreamSubscription<T> subscription;
    Timer? gapTimer;
    controller.onListen = () {
      subscription = listen(
        (e) {
          controller.add(e);
          gapTimer?.cancel();
          gapTimer = Timer(gap, () {
            subscription.cancel();
            controller.close();
          });
        },
        onError: controller.addError,
        onDone: controller.close,
      );
    };
    // Not handling pause/resume
    return controller.stream;
  }
}
