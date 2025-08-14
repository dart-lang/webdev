// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/loaders/ddc_library_bundle.dart';
import 'package:dwds/src/services/chrome_debug_exception.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/services/proxy_service.dart';
import 'package:dwds/src/services/web_socket_proxy_service.dart';
import 'package:dwds/src/utilities/synchronized.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// Type of requests added to the request controller.
typedef VmRequest = Map<String, Object>;

/// Type of responses added to the response controller.
typedef VmResponse = Map<String, Object?>;

enum _NamespacedServiceExtension {
  extDwdsEmitEvent(method: 'ext.dwds.emitEvent'),
  extDwdsReload(method: 'ext.dwds.reload'),
  extDwdsRestart(method: 'ext.dwds.restart'),
  extDwdsScreenshot(method: 'ext.dwds.screenshot'),
  extDwdsSendEvent(method: 'ext.dwds.sendEvent'),
  flutterListViews(method: '_flutter.listViews');

  const _NamespacedServiceExtension({required this.method});

  final String method;
}

/// Common interface for DWDS VM clients.
abstract class DwdsVmClient {
  /// The VM service client.
  VmService get client;

  /// Closes the VM client and releases resources.
  Future<void> close();
}

// Chrome-based DWDS VM client logger.
final _chromeLogger = Logger('DwdsVmClient');

// A client of the vm service that registers some custom extensions like
// hotRestart.
class ChromeDwdsVmClient implements DwdsVmClient {
  @override
  final VmService client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object?>> _responseController;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  /// Synchronizes hot restarts to avoid races.
  final _hotRestartQueue = AtomicQueue();

  ChromeDwdsVmClient(
    this.client,
    this._requestController,
    this._responseController,
  );

  @override
  Future<void> close() =>
      _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        await client.dispose();
      }();

  static Future<ChromeDwdsVmClient> create(
    ChromeDebugService debugService,
    DwdsStats dwdsStats,
    Uri? ddsUri,
  ) async {
    final chromeProxyService = debugService.chromeProxyService;
    final responseController = StreamController<VmResponse>();
    final responseSink = responseController.sink;
    // Response stream must be a broadcast stream so that it can have multiple
    // listeners:
    final responseStream = responseController.stream.asBroadcastStream();
    final requestController = StreamController<VmRequest>();
    final requestSink = requestController.sink;
    final requestStream = requestController.stream;

    final clientCompleter = Completer<VmService>();

    _setUpVmServerConnection(
      chromeProxyService: chromeProxyService,
      debugService: debugService,
      responseStream: responseStream,
      responseSink: responseSink,
      requestStream: requestStream,
      requestSink: requestSink,
      dwdsStats: dwdsStats,
      clientFuture: clientCompleter.future,
    );

    final client =
        ddsUri == null
            ? _setUpVmClient(
              responseStream: responseStream,
              requestController: requestController,
              requestSink: requestSink,
            )
            : await _setUpDdsClient(ddsUri: ddsUri);

    if (!clientCompleter.isCompleted) {
      clientCompleter.complete(client);
    }

    final dwdsVmClient = ChromeDwdsVmClient(
      client,
      requestController,
      responseController,
    );

    await _registerServiceExtensions(
      client: client,
      chromeProxyService: chromeProxyService,
      dwdsVmClient: dwdsVmClient,
    );

    return dwdsVmClient;
  }

  /// Establishes a VM service client that is connected via DDS and registers
  /// the service extensions on that client.
  static Future<VmService> _setUpDdsClient({required Uri ddsUri}) async {
    final client = await vmServiceConnectUri(ddsUri.toString());
    return client;
  }

  /// Establishes a VM service client that bypasses DDS and registers service
  /// extensions on that client.
  ///
  /// Note: This is only used in the rare cases where DDS is disabled.
  static VmService _setUpVmClient({
    required Stream<VmResponse> responseStream,
    required StreamSink<VmRequest> requestSink,
    required StreamController<VmRequest> requestController,
  }) {
    final client = VmService(responseStream.map(jsonEncode), (request) {
      if (requestController.isClosed) {
        _chromeLogger.warning(
          'Attempted to send a request but the connection is closed:\n\n'
          '$request',
        );
        return;
      }
      requestSink.add(Map<String, Object>.from(jsonDecode(request)));
    });

    return client;
  }

  /// Establishes a direct connection with the VM Server.
  ///
  /// This is used to register the [_NamespacedServiceExtension]s. Because
  /// namespaced service extensions are supposed to be registered by the engine,
  /// we need to register them on the VM server connection instead of via DDS.
  ///
  /// TODO(https://github.com/dart-lang/webdev/issues/1315): Ideally the engine
  /// should register all Flutter service extensions. However, to do so we will
  /// need to implement the missing isolate-related dart:developer APIs so that
  /// the engine has access to this information.
  static void _setUpVmServerConnection({
    required ChromeProxyService chromeProxyService,
    required DwdsStats dwdsStats,
    required ChromeDebugService debugService,
    required Stream<VmResponse> responseStream,
    required StreamSink<VmResponse> responseSink,
    required Stream<VmRequest> requestStream,
    required StreamSink<VmRequest> requestSink,
    required Future<VmService> clientFuture,
  }) {
    responseStream.listen((request) async {
      final response = await _maybeHandleServiceExtensionRequest(
        request,
        chromeProxyService: chromeProxyService,
        dwdsStats: dwdsStats,
        clientFuture: clientFuture,
      );
      if (response != null) {
        requestSink.add(response);
      }
    });

    final vmServerConnection = VmServerConnection(
      requestStream,
      responseSink,
      debugService.serviceExtensionRegistry,
      debugService.chromeProxyService,
    );

    for (final extension in _NamespacedServiceExtension.values) {
      debugService.serviceExtensionRegistry.registerExtension(
        extension.method,
        vmServerConnection,
      );
    }
  }

  static Future<VmRequest?> _maybeHandleServiceExtensionRequest(
    VmResponse request, {
    required ChromeProxyService chromeProxyService,
    required DwdsStats dwdsStats,
    required Future<VmService> clientFuture,
  }) async {
    VmRequest? response;
    final method = request['method'];
    if (method == _NamespacedServiceExtension.flutterListViews.method) {
      response = await flutterListViewsHandler(chromeProxyService);
    } else if (method == _NamespacedServiceExtension.extDwdsEmitEvent.method) {
      response = extDwdsEmitEventHandler(request, _chromeLogger);
    } else if (method == _NamespacedServiceExtension.extDwdsReload.method) {
      response = await _extDwdsReloadHandler(chromeProxyService);
    } else if (method == _NamespacedServiceExtension.extDwdsRestart.method) {
      final client = await clientFuture;
      response = await _extDwdsRestartHandler(chromeProxyService, client);
    } else if (method == _NamespacedServiceExtension.extDwdsSendEvent.method) {
      response = await extDwdsSendEventHandler(
        request,
        dwdsStats,
        _chromeLogger,
      );
    } else if (method == _NamespacedServiceExtension.extDwdsScreenshot.method) {
      response = await _extDwdsScreenshotHandler(chromeProxyService);
    }

    if (response != null) {
      response['id'] = request['id'] as String;
      // This is necessary even though DWDS doesn't use package:json_rpc_2.
      // Without it, the response will be treated as invalid:
      // https://github.com/dart-lang/json_rpc_2/blob/639857be892050159f5164c749d7947694976a4a/lib/src/server.dart#L252
      response['jsonrpc'] = '2.0';
    }

    return response;
  }

  static Future<Map<String, Object>> _extDwdsScreenshotHandler(
    ChromeProxyService chromeProxyService,
  ) async {
    await chromeProxyService.remoteDebugger.enablePage();
    final response = await chromeProxyService.remoteDebugger.sendCommand(
      'Page.captureScreenshot',
    );
    return {'result': response.result as Object};
  }

  static Future<Map<String, Object>> _extDwdsReloadHandler(
    ChromeProxyService chromeProxyService,
  ) async {
    await _fullReload(chromeProxyService);
    return {'result': Success().toJson()};
  }

  static Future<Map<String, Object>> _extDwdsRestartHandler(
    ChromeProxyService chromeProxyService,
    VmService client,
  ) async {
    await _hotRestart(chromeProxyService, client);
    return {'result': Success().toJson()};
  }

  static Future<void> _registerServiceExtensions({
    required VmService client,
    required ChromeProxyService chromeProxyService,
    required ChromeDwdsVmClient dwdsVmClient,
  }) async {
    client.registerServiceCallback(
      'hotRestart',
      (request) => captureElapsedTime(
        () => dwdsVmClient.hotRestart(chromeProxyService, client),
        (_) => DwdsEvent.hotRestart(),
      ),
    );
    await client.registerService('hotRestart', 'DWDS');

    client.registerServiceCallback(
      'fullReload',
      (request) => captureElapsedTime(
        () => _fullReload(chromeProxyService),
        (_) => DwdsEvent.fullReload(),
      ),
    );
    await client.registerService('fullReload', 'DWDS');
  }

  Future<Map<String, dynamic>> hotRestart(
    ChromeProxyService chromeProxyService,
    VmService client,
  ) {
    return _hotRestartQueue.run(() => _hotRestart(chromeProxyService, client));
  }
}

// WebSocket-based DWDS VM client logger.
final _webSocketLogger = Logger('WebSocketDwdsVmClient');

/// WebSocket-based DWDS VM client.
class WebSocketDwdsVmClient implements DwdsVmClient {
  @override
  final VmService client;
  final StreamController<VmRequest> _requestController;
  final StreamController<VmResponse> _responseController;
  Future<void>? _closed;

  WebSocketDwdsVmClient(
    this.client,
    this._requestController,
    this._responseController,
  );

  @override
  Future<void> close() =>
      _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        await client.dispose();
      }();

  static Future<WebSocketDwdsVmClient> create(
    WebSocketDebugService debugService,
  ) async {
    _webSocketLogger.fine('Creating WebSocket DWDS VM client');
    final webSocketProxyService = debugService.webSocketProxyService;
    final responseController = StreamController<VmResponse>();
    final responseSink = responseController.sink;
    final responseStream = responseController.stream.asBroadcastStream();
    final requestController = StreamController<VmRequest>();
    final requestSink = requestController.sink;
    final requestStream = requestController.stream;

    _setUpWebSocketVmServerConnection(
      webSocketProxyService: webSocketProxyService,
      debugService: debugService,
      responseStream: responseStream,
      responseSink: responseSink,
      requestStream: requestStream,
      requestSink: requestSink,
    );

    final client = _setUpWebSocketVmClient(
      responseStream: responseStream,
      requestController: requestController,
      requestSink: requestSink,
    );

    await _registerServiceExtensions(
      client: client,
      webSocketProxyService: webSocketProxyService,
    );

    _webSocketLogger.fine('WebSocket DWDS VM client created successfully');
    return WebSocketDwdsVmClient(client, requestController, responseController);
  }

  static VmService _setUpWebSocketVmClient({
    required Stream<VmResponse> responseStream,
    required StreamSink<VmRequest> requestSink,
    required StreamController<VmRequest> requestController,
  }) {
    final client = VmService(responseStream.map(jsonEncode), (request) {
      if (requestController.isClosed) {
        _webSocketLogger.warning(
          'Attempted to send a request but the connection is closed:\n\n$request',
        );
        return;
      }
      requestSink.add(Map<String, Object>.from(jsonDecode(request)));
    });
    return client;
  }

  static void _setUpWebSocketVmServerConnection({
    required WebSocketProxyService webSocketProxyService,
    required WebSocketDebugService debugService,
    required Stream<VmResponse> responseStream,
    required StreamSink<VmResponse> responseSink,
    required Stream<VmRequest> requestStream,
    required StreamSink<VmRequest> requestSink,
  }) {
    responseStream.listen((request) async {
      final response = await _maybeHandleWebSocketServiceExtensionRequest(
        request,
        webSocketProxyService: webSocketProxyService,
      );
      if (response != null) {
        requestSink.add(response);
      }
    });

    final vmServerConnection = VmServerConnection(
      requestStream,
      responseSink,
      debugService.serviceExtensionRegistry,
      webSocketProxyService,
    );

    // Register service extensions
    for (final extension in _NamespacedServiceExtension.values) {
      _webSocketLogger.finest(
        'Registering service extension: ${extension.method}',
      );
      debugService.serviceExtensionRegistry.registerExtension(
        extension.method,
        vmServerConnection,
      );
    }
  }

  static Future<VmRequest?> _maybeHandleWebSocketServiceExtensionRequest(
    VmResponse request, {
    required WebSocketProxyService webSocketProxyService,
  }) async {
    VmRequest? response;
    final method = request['method'];

    _webSocketLogger.finest('Processing service extension method: $method');

    if (method == _NamespacedServiceExtension.flutterListViews.method) {
      response = await flutterListViewsHandler(webSocketProxyService);
    } else if (method == _NamespacedServiceExtension.extDwdsEmitEvent.method) {
      response = extDwdsEmitEventHandler(request, _webSocketLogger);
    } else if (method == _NamespacedServiceExtension.extDwdsReload.method) {
      response = {'result': 'Reload not implemented'};
    } else if (method == _NamespacedServiceExtension.extDwdsSendEvent.method) {
      response = await extDwdsSendEventHandler(request, null, _webSocketLogger);
    } else if (method == _NamespacedServiceExtension.extDwdsScreenshot.method) {
      response = {'result': 'Screenshot not implemented'};
    }

    if (response != null) {
      response['id'] = request['id'] as String;
      response['jsonrpc'] = '2.0';
    }
    return response;
  }

  static Future<void> _registerServiceExtensions({
    required VmService client,
    required WebSocketProxyService webSocketProxyService,
  }) async {
    client.registerServiceCallback(
      'hotRestart',
      (request) => captureElapsedTime(
        () => webSocketProxyService.hotRestart(),
        (_) => DwdsEvent.hotRestart(),
      ),
    );
    await client.registerService('hotRestart', 'DWDS');
  }
}

/// Shared handler for Flutter list views service extension.
Future<Map<String, Object>> flutterListViewsHandler(
  ProxyService proxyService,
) async {
  final vm = await proxyService.getVM();
  final isolates = vm.isolates;
  return <String, Object>{
    'result': <String, Object>{
      'views': <Object>[
        for (final isolate in isolates ?? [])
          <String, Object>{'id': isolate.id, 'isolate': isolate.toJson()},
      ],
    },
  };
}

/// Shared handler for DWDS emit event service extension.
Map<String, Object> extDwdsEmitEventHandler(VmResponse request, Logger logger) {
  final event = request['params'] as Map<String, dynamic>?;
  if (event != null) {
    final type = event['type'] as String?;
    final payload = event['payload'] as Map<String, dynamic>?;
    if (type != null && payload != null) {
      logger.fine('EmitEvent: $type $payload');
      emitEvent(DwdsEvent(type, payload));
    }
  }
  return {'result': Success().toJson()};
}

/// Shared handler for DWDS send event service extension.
Future<Map<String, Object>> extDwdsSendEventHandler(
  VmResponse request,
  DwdsStats? dwdsStats,
  Logger logger,
) async {
  logger.fine('SendEvent: $request');
  if (dwdsStats != null) {
    _processSendEvent(request, dwdsStats);
  }
  return {'result': Success().toJson()};
}

void _processSendEvent(Map<String, dynamic> request, DwdsStats dwdsStats) {
  final event = request['params'] as Map<String, dynamic>?;
  if (event == null) return;
  final type = event['type'] as String?;
  final payload = event['payload'] as Map<String, dynamic>?;
  switch (type) {
    case 'DevtoolsEvent':
      {
        _chromeLogger.finest('Received DevTools event: $event');
        final action = payload?['action'] as String?;
        final screen = payload?['screen'] as String?;
        if (screen != null && action == 'pageReady') {
          _recordDwdsStats(dwdsStats, screen);
        } else {
          _chromeLogger.finest('Ignoring unknown event: $event');
        }
      }
  }
}

void _recordDwdsStats(DwdsStats dwdsStats, String screen) {
  if (dwdsStats.isFirstDebuggerReady) {
    final devToolsStart = dwdsStats.devToolsStart;
    final debuggerStart = dwdsStats.debuggerStart;
    if (devToolsStart != null) {
      final devToolLoadTime =
          DateTime.now().difference(devToolsStart).inMilliseconds;
      emitEvent(DwdsEvent.devToolsLoad(devToolLoadTime, screen));
      _chromeLogger.fine('DevTools load time: $devToolLoadTime ms');
    }
    if (debuggerStart != null) {
      final debuggerReadyTime =
          DateTime.now().difference(debuggerStart).inMilliseconds;
      emitEvent(DwdsEvent.debuggerReady(debuggerReadyTime, screen));
      _chromeLogger.fine('Debugger ready time: $debuggerReadyTime ms');
    }
  } else {
    _chromeLogger.finest('Debugger and DevTools stats are already recorded.');
  }
}

Future<int> tryGetContextId(
  ChromeProxyService chromeProxyService, {
  int retries = 3,
}) async {
  const waitInMs = 50;
  for (var retry = 0; retry < retries; retry++) {
    final tryId = await chromeProxyService.executionContext.id;
    if (tryId != null) return tryId;
    await Future.delayed(const Duration(milliseconds: waitInMs));
  }
  throw StateError('No context with the running Dart application.');
}

Future<Map<String, dynamic>> _hotRestart(
  ChromeProxyService chromeProxyService,
  VmService client,
) async {
  _chromeLogger.info('Attempting a hot restart');

  chromeProxyService.terminatingIsolates = true;
  await _disableBreakpointsAndResume(client, chromeProxyService);
  try {
    _chromeLogger.info('Attempting to get execution context ID.');
    await tryGetContextId(chromeProxyService);
    _chromeLogger.info('Got execution context ID.');
  } on StateError catch (e) {
    // We couldn't find the execution context. `hotRestart` may have been
    // triggered in the middle of a full reload.
    return {
      'error': {'code': RPCErrorKind.kInternalError.code, 'message': e.message},
    };
  }
  // Start listening for isolate create events before issuing a hot
  // restart. Only return success after the isolate has fully started.
  final stream = chromeProxyService.onEvent('Isolate');
  final waitForIsolateStarted = stream.firstWhere(
    (event) => event.kind == EventKind.kIsolateStart,
  );
  try {
    // If we should pause isolates on start, then only run main once we get a
    // resume event.
    final pauseIsolatesOnStart = chromeProxyService.pauseIsolatesOnStart;
    if (pauseIsolatesOnStart) {
      _waitForResumeEventToRunMain(chromeProxyService);
    }
    // Generate run id to hot restart all apps loaded into the tab.
    final runId = const Uuid().v4().toString();

    // When using the DDC library bundle format, we determine the sources that
    // were reloaded during a hot restart to then wait until all the sources are
    // parsed before finishing hot restart. This is necessary before we can
    // recompute any source location metadata in the `ChromeProxyService`.
    // TODO(srujzs): We don't do this for the AMD module format, should we? It
    // would require adding an extra parameter in the AMD strategy. As we're
    // planning to deprecate it, for now, do nothing.
    final isDdcLibraryBundle =
        globalToolConfiguration.loadStrategy is DdcLibraryBundleStrategy;
    final computedReloadedSrcs = Completer<void>();
    final reloadedSrcs = <String>{};
    late StreamSubscription<String> parsedScriptsSubscription;
    if (isDdcLibraryBundle) {
      // Injected client should send a request to recreate the isolate after the
      // hot restart. The creation of the isolate should in turn wait until all
      // scripts are parsed.
      chromeProxyService.allowedToCreateIsolate = Completer<void>();
      final debugger = await chromeProxyService.debuggerFuture;
      parsedScriptsSubscription = debugger.parsedScriptsController.stream
          .listen((url) {
            computedReloadedSrcs.future.then((_) async {
              reloadedSrcs.remove(Uri.parse(url).normalizePath().path);
              if (reloadedSrcs.isEmpty &&
                  !chromeProxyService.allowedToCreateIsolate.isCompleted) {
                chromeProxyService.allowedToCreateIsolate.complete();
              }
            });
          });
    }
    _chromeLogger.info('Issuing \$dartHotRestartDwds request');
    final remoteObject = await chromeProxyService.inspector.jsEvaluate(
      '\$dartHotRestartDwds(\'$runId\', $pauseIsolatesOnStart);',
      awaitPromise: true,
      returnByValue: true,
    );
    if (isDdcLibraryBundle) {
      final reloadedSrcModuleLibraries =
          (remoteObject.value as List).cast<Map>();
      for (final srcModuleLibrary in reloadedSrcModuleLibraries) {
        final srcModuleLibraryCast = srcModuleLibrary.cast<String, Object>();
        reloadedSrcs.add(
          Uri.parse(srcModuleLibraryCast['src'] as String).normalizePath().path,
        );
      }
      if (reloadedSrcs.isEmpty) {
        chromeProxyService.allowedToCreateIsolate.complete();
      }
      computedReloadedSrcs.complete();
      await chromeProxyService.allowedToCreateIsolate.future;
      await parsedScriptsSubscription.cancel();
    } else {
      assert(remoteObject.value == null);
    }
    _chromeLogger.info('\$dartHotRestartDwds request complete.');
  } on WipError catch (exception) {
    final code = exception.error?['code'];
    final message = exception.error?['message'];
    // This corresponds to `Execution context was destroyed` which can
    // occur during a hot restart that must fall back to a full reload.
    if (code != RPCErrorKind.kServerError.code) {
      return {
        'error': {'code': code, 'message': message, 'data': exception},
      };
    }
  } on ChromeDebugException catch (exception) {
    // Exceptions thrown by the injected client during hot restart.
    return {
      'error': {
        'code': RPCErrorKind.kInternalError.code,
        'message': '$exception',
      },
    };
  }
  _chromeLogger.info('Waiting for Isolate Start event.');
  await waitForIsolateStarted;
  chromeProxyService.terminatingIsolates = false;

  _chromeLogger.info('Successful hot restart');
  return {'result': Success().toJson()};
}

void _waitForResumeEventToRunMain(ChromeProxyService chromeProxyService) {
  StreamSubscription<String>? resumeEventsSubscription;
  resumeEventsSubscription = chromeProxyService.resumeAfterRestartEventsStream
      .listen((_) async {
        await resumeEventsSubscription!.cancel();
        await chromeProxyService.inspector.jsEvaluate(
          '\$dartReadyToRunMain();',
        );
      });
}

Future<Map<String, dynamic>> _fullReload(
  ChromeProxyService chromeProxyService,
) async {
  _chromeLogger.info('Attempting a full reload');
  await chromeProxyService.remoteDebugger.enablePage();
  await chromeProxyService.remoteDebugger.pageReload();
  _chromeLogger.info('Successful full reload');
  return {'result': Success().toJson()};
}

Future<void> _disableBreakpointsAndResume(
  VmService client,
  ChromeProxyService chromeProxyService,
) async {
  _chromeLogger.info(
    'Attempting to disable breakpoints and resume the isolate',
  );
  final vm = await client.getVM();
  final isolates = vm.isolates;
  if (isolates == null || isolates.isEmpty) {
    throw StateError('No active isolate to resume.');
  }
  final isolateId = isolates.first.id;
  if (isolateId == null) {
    throw StateError('No active isolate to resume.');
  }
  await chromeProxyService.disableBreakpoints();
  try {
    // Any checks for paused status result in race conditions or hangs
    // at this point:
    //
    // - `getIsolate()` and check for status:
    //    the app might still pause on existing breakpoint.
    //
    // - `pause()` and wait for `Debug.paused` event:
    //   chrome does not send the `Debug.Paused `notification
    //   without shifting focus to chrome.
    //
    // Instead, just try resuming and
    // ignore failures indicating that the app is already running:
    //
    // WipError -32000 Can only perform operation while paused.
    await client.resume(isolateId);
  } on RPCError catch (e, s) {
    if (!e.message.contains('Can only perform operation while paused')) {
      _chromeLogger.severe(
        'Hot restart failed to resume exiting isolate',
        e,
        s,
      );
      rethrow;
    }
  }
  _chromeLogger.info(
    'Successfully disabled breakpoints and resumed the isolate',
  );
}
