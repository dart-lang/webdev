// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/chrome_debug_exception.dart';
import 'package:dwds/src/services/chrome_proxy_service.dart';
import 'package:dwds/src/services/debug_service.dart';
import 'package:dwds/src/utilities/synchronized.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:vm_service_interface/vm_service_interface.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

final _logger = Logger('DwdsVmClient');

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

// A client of the vm service that registers some custom extensions like
// hotRestart.
class DwdsVmClient {
  final VmService client;
  final StreamController<Map<String, Object>> _requestController;
  final StreamController<Map<String, Object?>> _responseController;

  /// Null until [close] is called.
  ///
  /// All subsequent calls to [close] will return this future.
  Future<void>? _closed;

  /// Synchronizes hot restarts to avoid races.
  final _hotRestartQueue = AtomicQueue();

  DwdsVmClient(this.client, this._requestController, this._responseController);

  Future<void> close() =>
      _closed ??= () async {
        await _requestController.close();
        await _responseController.close();
        await client.dispose();
      }();

  static Future<DwdsVmClient> create(
    DebugService debugService,
    DwdsStats dwdsStats,
    Uri? ddsUri,
  ) async {
    final chromeProxyService =
        debugService.chromeProxyService as ChromeProxyService;
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

    final dwdsVmClient = DwdsVmClient(
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
        _logger.warning(
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
    required DebugService debugService,
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
      response = await _flutterListViewsHandler(chromeProxyService);
    } else if (method == _NamespacedServiceExtension.extDwdsEmitEvent.method) {
      response = _extDwdsEmitEventHandler(request);
    } else if (method == _NamespacedServiceExtension.extDwdsReload.method) {
      response = await _extDwdsReloadHandler(chromeProxyService);
    } else if (method == _NamespacedServiceExtension.extDwdsRestart.method) {
      final client = await clientFuture;
      response = await _extDwdsRestartHandler(chromeProxyService, client);
    } else if (method == _NamespacedServiceExtension.extDwdsSendEvent.method) {
      response = await _extDwdsSendEventHandler(request, dwdsStats);
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

  static Future<Map<String, Object>> _flutterListViewsHandler(
    ChromeProxyService chromeProxyService,
  ) async {
    final vm = await chromeProxyService.getVM();
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

  static Future<Map<String, Object>> _extDwdsScreenshotHandler(
    ChromeProxyService chromeProxyService,
  ) async {
    await chromeProxyService.remoteDebugger.enablePage();
    final response = await chromeProxyService.remoteDebugger.sendCommand(
      'Page.captureScreenshot',
    );
    return {'result': response.result as Object};
  }

  static Future<Map<String, Object>> _extDwdsSendEventHandler(
    VmResponse request,
    DwdsStats dwdsStats,
  ) async {
    _processSendEvent(request, dwdsStats);
    return {'result': Success().toJson()};
  }

  static Map<String, Object> _extDwdsEmitEventHandler(VmResponse request) {
    final event = request['params'] as Map<String, dynamic>?;
    if (event != null) {
      final type = event['type'] as String?;
      final payload = event['payload'] as Map<String, dynamic>?;
      if (type != null && payload != null) {
        emitEvent(DwdsEvent(type, payload));
      }
    }

    return {'result': Success().toJson()};
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
    required DwdsVmClient dwdsVmClient,
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

void _processSendEvent(Map<String, dynamic> request, DwdsStats dwdsStats) {
  final event = request['params'] as Map<String, dynamic>?;
  if (event == null) return;
  final type = event['type'] as String?;
  final payload = event['payload'] as Map<String, dynamic>?;
  switch (type) {
    case 'DevtoolsEvent':
      {
        _logger.finest('Received DevTools event: $event');
        final action = payload?['action'] as String?;
        final screen = payload?['screen'] as String?;
        if (screen != null && action == 'pageReady') {
          _recordDwdsStats(dwdsStats, screen);
        } else {
          _logger.finest('Ignoring unknown event: $event');
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
      _logger.fine('DevTools load time: $devToolLoadTime ms');
    }
    if (debuggerStart != null) {
      final debuggerReadyTime =
          DateTime.now().difference(debuggerStart).inMilliseconds;
      emitEvent(DwdsEvent.debuggerReady(debuggerReadyTime, screen));
      _logger.fine('Debugger ready time: $debuggerReadyTime ms');
    }
  } else {
    _logger.finest('Debugger and DevTools stats are already recorded.');
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
  _logger.info('Attempting a hot restart');

  chromeProxyService.terminatingIsolates = true;
  await _disableBreakpointsAndResume(client, chromeProxyService);
  try {
    _logger.info('Attempting to get execution context ID.');
    await tryGetContextId(chromeProxyService);
    _logger.info('Got execution context ID.');
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
  try {
    // If we should pause isolates on start, then only run main once we get a
    // resume event.
    final pauseIsolatesOnStart = chromeProxyService.pauseIsolatesOnStart;
    if (pauseIsolatesOnStart) {
      _waitForResumeEventToRunMain(chromeProxyService);
    }
    // Generate run id to hot restart all apps loaded into the tab.
    final runId = const Uuid().v4().toString();
    _logger.info('Issuing \$dartHotRestartDwds request');
    await chromeProxyService.inspector.jsEvaluate(
      '\$dartHotRestartDwds(\'$runId\', $pauseIsolatesOnStart);',
      awaitPromise: true,
    );
    _logger.info('\$dartHotRestartDwds request complete.');
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
  _logger.info('Waiting for Isolate Start event.');
  await stream.firstWhere((event) => event.kind == EventKind.kIsolateStart);
  chromeProxyService.terminatingIsolates = false;

  _logger.info('Successful hot restart');
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
  _logger.info('Attempting a full reload');
  await chromeProxyService.remoteDebugger.enablePage();
  await chromeProxyService.remoteDebugger.pageReload();
  _logger.info('Successful full reload');
  return {'result': Success().toJson()};
}

Future<void> _disableBreakpointsAndResume(
  VmService client,
  ChromeProxyService chromeProxyService,
) async {
  _logger.info('Attempting to disable breakpoints and resume the isolate');
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
      _logger.severe('Hot restart failed to resume exiting isolate', e, s);
      rethrow;
    }
  }
  _logger.info('Successfully disabled breakpoints and resumed the isolate');
}
