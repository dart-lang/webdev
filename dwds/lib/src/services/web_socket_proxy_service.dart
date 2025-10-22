// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/data/debug_event.dart';
import 'package:dwds/data/hot_reload_request.dart';
import 'package:dwds/data/hot_reload_response.dart';
import 'package:dwds/data/hot_restart_request.dart';
import 'package:dwds/data/hot_restart_response.dart';
import 'package:dwds/data/register_event.dart';
import 'package:dwds/data/service_extension_request.dart';
import 'package:dwds/data/service_extension_response.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/services/proxy_service.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service.dart';

/// Defines callbacks for sending messages to the connected client.
/// Returns the number of clients the request was successfully sent to.
typedef SendClientRequest = int Function(Object request);

const _pauseIsolatesOnStartFlag = 'pause_isolates_on_start';

/// Grace period before destroying isolate when no clients are detected.
/// This handles the race condition during page refresh where the old connection
/// closes before the new connection is established, preventing premature isolate destruction.
const _isolateDestructionGracePeriod = Duration(seconds: 15);

/// Error message when no clients are available for hot reload/restart.
const kNoClientsAvailable = 'No clients available.';

/// Tracks hot reload responses from multiple browser windows/tabs.
class _HotReloadTracker {
  final String requestId;
  final Completer<HotReloadResponse> completer;
  final int expectedResponses;
  final List<HotReloadResponse> responses = [];
  final Timer timeoutTimer;

  _HotReloadTracker({
    required this.requestId,
    required this.completer,
    required this.expectedResponses,
    required this.timeoutTimer,
  });

  bool get gotAllResponses => responses.length >= expectedResponses;

  void addResponse(HotReloadResponse response) {
    responses.add(response);
  }

  bool get allSuccessful => responses.every((r) => r.success);

  void dispose() {
    timeoutTimer.cancel();
  }
}

/// Tracks hot restart responses from multiple browser windows/tabs.
class _HotRestartTracker {
  final String requestId;
  final Completer<HotRestartResponse> completer;
  final int expectedResponses;
  final List<HotRestartResponse> responses = [];
  final Timer timeoutTimer;

  _HotRestartTracker({
    required this.requestId,
    required this.completer,
    required this.expectedResponses,
    required this.timeoutTimer,
  });

  bool get gotAllResponses => responses.length >= expectedResponses;

  void addResponse(HotRestartResponse response) {
    responses.add(response);
  }

  bool get allSuccessful => responses.every((r) => r.success);

  void dispose() {
    timeoutTimer.cancel();
  }
}

/// Tracks service extension responses from multiple browser windows/tabs.
class _ServiceExtensionTracker {
  final String requestId;
  final Completer<ServiceExtensionResponse> completer;
  final int expectedResponses;
  final List<ServiceExtensionResponse> responses = [];
  final Timer timeoutTimer;

  _ServiceExtensionTracker({
    required this.requestId,
    required this.completer,
    required this.expectedResponses,
    required this.timeoutTimer,
  });

  bool get gotAllResponses => responses.length >= expectedResponses;

  void addResponse(ServiceExtensionResponse response) {
    responses.add(response);
  }

  bool get allSuccessful => responses.every((r) => r.success);

  void dispose() {
    timeoutTimer.cancel();
  }
}

/// Exception thrown when no browser clients are connected to DWDS.
class NoClientsAvailableException implements Exception {
  final String message;

  NoClientsAvailableException._(this.message);

  @override
  String toString() => 'NoClientsAvailableException: $message';
}

/// WebSocket-based VM service proxy for web debugging.
class WebSocketProxyService extends ProxyService {
  final _logger = Logger('WebSocketProxyService');

  /// Active service extension trackers by request ID.
  final Map<String, _ServiceExtensionTracker> _pendingServiceExtensionTrackers =
      {};

  /// Sends messages to the client.
  final SendClientRequest sendClientRequest;

  /// App connection for this service.
  AppConnection appConnection;

  /// Active hot reload trackers by request ID.
  final Map<String, _HotReloadTracker> _pendingHotReloads = {};

  /// Active hot restart trackers by request ID.
  final Map<String, _HotRestartTracker> _pendingHotRestarts = {};

  /// App connection cleanup subscriptions by connection instance ID.
  final Map<String, StreamSubscription<void>> _appConnectionDoneSubscriptions =
      {};

  /// Active connection count for this service.
  int _activeConnectionCount = 0;

  /// Counter for generating unique isolate IDs across page refreshes
  static int _globalIsolateIdCounter = 0;

  bool get _isIsolateRunning => _isolateRunning;

  WebSocketProxyService._(
    this.sendClientRequest,
    vm_service.VM vm,
    this.appConnection,
  ) : super(vm); // Isolate state
  vm_service.IsolateRef? _isolateRef;
  bool _isolateRunning = false;
  vm_service.Event? _currentPauseEvent;
  bool _mainHasStarted = false;

  /// Creates a new isolate for WebSocket debugging.
  @override
  Future<void> createIsolate(
    AppConnection appConnection, {
    bool newConnection = false,
  }) async {
    // Update app connection
    this.appConnection = appConnection;

    // Track this connection
    final connectionId = appConnection.request.instanceId;

    // Check if this connection is already being tracked
    final isNewConnection =
        newConnection ||
        !_appConnectionDoneSubscriptions.containsKey(connectionId);

    if (isNewConnection) {
      _activeConnectionCount++;
      _logger.fine(
        'Adding new connection: $connectionId (total: $_activeConnectionCount)',
      );
    } else {
      _logger.fine(
        'Reconnecting existing connection: $connectionId (total: $_activeConnectionCount)',
      );
    }

    // Auto-cleanup on connection close
    final existingSubscription = _appConnectionDoneSubscriptions[connectionId];
    await existingSubscription?.cancel();
    _appConnectionDoneSubscriptions[connectionId] = appConnection.onDone
        .asStream()
        .listen((_) {
          _handleConnectionClosed(connectionId);
        });

    // If we already have a running isolate, just update the connection and return
    if (_isIsolateRunning && _isolateRef != null) {
      _logger.fine(
        'Reusing existing isolate ${_isolateRef!.id} for connection: $connectionId',
      );
      return;
    }

    // Create isolate reference with unique ID
    final isolateId = '${++_globalIsolateIdCounter}';
    final isolateRef = vm_service.IsolateRef(
      id: isolateId,
      name: 'main()',
      number: isolateId,
      isSystemIsolate: false,
    );

    _isolateRef = isolateRef;
    _isolateRunning = true;
    vm.isolates?.add(isolateRef);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    _logger.fine(
      'Created new isolate: $isolateId for connection: $connectionId',
    );

    // Send lifecycle events
    _streamNotify(
      vm_service.EventStreams.kIsolate,
      vm_service.Event(
        kind: vm_service.EventKind.kIsolateStart,
        timestamp: timestamp,
        isolate: isolateRef,
      ),
    );
    _streamNotify(
      vm_service.EventStreams.kIsolate,
      vm_service.Event(
        kind: vm_service.EventKind.kIsolateRunnable,
        timestamp: timestamp,
        isolate: isolateRef,
      ),
    );

    // Send pause event if enabled
    if (pauseIsolatesOnStart) {
      final pauseEvent = vm_service.Event(
        kind: vm_service.EventKind.kPauseStart,
        timestamp: timestamp,
        isolate: isolateRef,
      );
      _currentPauseEvent = pauseEvent;
      _streamNotify(vm_service.EventStreams.kDebug, pauseEvent);
    }

    // Complete initialization after isolate is set up
    if (!initializedCompleter.isCompleted) initializedCompleter.complete();
  }

  /// Handles a connection being closed.
  void _handleConnectionClosed(String connectionId) {
    _logger.fine('Connection closed: $connectionId');

    // Only decrement if this connection was actually being tracked
    if (_appConnectionDoneSubscriptions.containsKey(connectionId)) {
      // Remove the subscription for this connection
      _appConnectionDoneSubscriptions[connectionId]?.cancel();
      _appConnectionDoneSubscriptions.remove(connectionId);

      // Decrease active connection count
      _activeConnectionCount--;
      _logger.fine(
        'Removed connection: $connectionId (remaining: $_activeConnectionCount)',
      );
      _logger.fine(
        'Current tracked connections: ${_appConnectionDoneSubscriptions.keys.toList()}',
      );

      // Instead of destroying the isolate immediately, check if there are still
      // clients that can receive hot reload requests
      if (_activeConnectionCount <= 0) {
        // Double-check by asking the sendClientRequest callback how many clients are available
        final actualClientCount = sendClientRequest({'type': 'ping'});
        _logger.fine(
          'Actual client count from sendClientRequest: $actualClientCount',
        );

        if (actualClientCount == 0) {
          _logger.fine(
            'No clients available for hot reload, scheduling isolate destruction',
          );
          // Add a delay before destroying the isolate to handle page refresh race condition
          Timer(_isolateDestructionGracePeriod, () {
            // Double-check client count again before destroying
            final finalClientCount = sendClientRequest({'type': 'ping'});
            if (finalClientCount == 0) {
              _logger.fine(
                'Final check confirmed no clients, destroying isolate',
              );
              destroyIsolate();
            } else {
              _logger.fine(
                'Final check found $finalClientCount clients, keeping isolate alive',
              );
              _activeConnectionCount = finalClientCount;
            }
          });
        } else {
          _logger.fine(
            'Still have $actualClientCount clients available, keeping isolate alive',
          );
          // Update our internal counter to match reality
          _activeConnectionCount = actualClientCount;
        }
      } else {
        _logger.fine(
          'Still have $_activeConnectionCount active connections, keeping isolate alive',
        );
      }
    } else {
      _logger.warning(
        'Attempted to close connection that was not tracked: $connectionId',
      );
    }
  }

  /// Destroys the isolate and cleans up state.
  @override
  void destroyIsolate() {
    _logger.fine('Destroying isolate');

    if (!_isIsolateRunning) {
      _logger.fine('Isolate already destroyed, ignoring');
      return;
    }

    final isolateRef = _isolateRef;

    // Cancel all connection subscriptions
    for (final subscription in _appConnectionDoneSubscriptions.values) {
      subscription.cancel();
    }
    _appConnectionDoneSubscriptions.clear();
    _activeConnectionCount = 0;

    // Send exit event
    if (isolateRef != null) {
      _streamNotify(
        vm_service.EventStreams.kIsolate,
        vm_service.Event(
          kind: vm_service.EventKind.kIsolateExit,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: isolateRef,
        ),
      );
    }

    vm.isolates?.removeWhere((ref) => ref.id == isolateRef?.id);

    // Reset state
    _isolateRef = null;
    _isolateRunning = false;
    _currentPauseEvent = null;
    _mainHasStarted = false;

    if (initializedCompleter.isCompleted) {
      initializedCompleter = Completer<void>();
    }
  }

  /// Sends events to stream controllers.
  void _streamNotify(String streamId, vm_service.Event event) {
    final controller = streamControllers[streamId];
    if (controller == null) return;
    controller.add(event);
  }

  @override
  Future<Success> setLibraryDebuggable(
    String isolateId,
    String libraryId,
    bool isDebuggable,
  ) {
    return rpcNotSupportedFuture('setLibraryDebuggable');
  }

  @override
  Future<Success> setIsolatePauseMode(
    String isolateId, {
    String? exceptionPauseMode,
    bool? shouldPauseOnExit,
  }) async {
    // Not supported in WebSocket mode - return success for compatibility
    return Success();
  }

  @override
  Future<vm_service.Isolate> getIsolate(String isolateId) =>
      wrapInErrorHandlerAsync('getIsolate', () => _getIsolate(isolateId));

  Future<vm_service.Isolate> _getIsolate(String isolateId) async {
    if (!_isIsolateRunning || _isolateRef == null) {
      throw vm_service.RPCError(
        'getIsolate',
        vm_service.RPCErrorKind.kInvalidParams.code,
        'No running isolate found for id: $isolateId',
      );
    }
    if (_isolateRef!.id != isolateId) {
      throw vm_service.RPCError(
        'getIsolate',
        vm_service.RPCErrorKind.kInvalidParams.code,
        'Isolate with id $isolateId not found.',
      );
    }

    return vm_service.Isolate(
      id: _isolateRef!.id!,
      name: _isolateRef!.name,
      number: _isolateRef!.number,
      startTime: DateTime.now().millisecondsSinceEpoch,
      isSystemIsolate: _isolateRef!.isSystemIsolate,
      runnable: true,
      pauseEvent: _currentPauseEvent,
    );
  }

  /// Adds events to stream controllers.
  void addEvent(String streamId, vm_service.Event event) {
    final controller = streamControllers[streamId];
    if (controller != null && !controller.isClosed) {
      controller.add(event);
    } else {
      _logger.warning('Cannot add event to closed/missing stream: $streamId');
    }
  }

  static Future<WebSocketProxyService> create(
    SendClientRequest sendClientRequest,
    AppConnection appConnection,
  ) async {
    final vm = vm_service.VM(
      name: 'WebSocketDebugProxy',
      operatingSystem: 'web',
      startTime: DateTime.now().millisecondsSinceEpoch,
      version: 'unknown',
      isolates: [],
      isolateGroups: [],
      systemIsolates: [],
      systemIsolateGroups: [],
      targetCPU: 'Web',
      hostCPU: 'DWDS',
      architectureBits: -1,
      pid: -1,
    );
    final service = WebSocketProxyService._(
      sendClientRequest,
      vm,
      appConnection,
    );
    safeUnawaited(service.createIsolate(appConnection));
    return service;
  }

  /// Returns the root VM object.
  @override
  Future<vm_service.VM> getVM() => wrapInErrorHandlerAsync('getVM', _getVM);

  Future<vm_service.VM> _getVM() {
    return captureElapsedTime(() async {
      // Ensure the VM's isolate list is synchronized with our actual state
      if (_isIsolateRunning && _isolateRef != null) {
        // Make sure our isolate is in the VM's isolate list
        final isolateExists =
            vm.isolates?.any((ref) => ref.id == _isolateRef!.id) ?? false;
        if (!isolateExists) {
          vm.isolates?.add(_isolateRef!);
        }
      } else {
        // If no isolate is running, make sure the list is empty
        vm.isolates?.clear();
      }

      return vm;
    }, (result) => DwdsEvent.getVM());
  }

  /// Not available in WebSocket mode.
  dynamic get remoteDebugger {
    throw UnsupportedError(
      'remoteDebugger not available in WebSocketProxyService.\n'
      'Called from:\n${StackTrace.current}',
    );
  }

  @override
  Future<vm_service.ReloadReport> reloadSources(
    String isolateId, {
    bool? force,
    bool? pause,
    String? rootLibUri,
    String? packagesUri,
  }) async {
    _logger.info('Attempting a hot reload');
    try {
      await _performWebSocketHotReload();
      _logger.info('Hot reload completed successfully');
      return _ReloadReportWithMetadata(success: true);
    } on NoClientsAvailableException catch (e) {
      // Throw RPC error with kIsolateCannotReload code when no browser clients are
      // connected.
      throw vm_service.RPCError(
        'reloadSources',
        vm_service.RPCErrorKind.kIsolateCannotReload.code,
        'Hot reload failed: ${e.message}',
      );
    } catch (e) {
      _logger.warning('Hot reload failed: $e');
      return _ReloadReportWithMetadata(success: false, notices: [e.toString()]);
    }
  }

  /// Handles hot restart requests.
  Future<Map<String, dynamic>> hotRestart() async {
    _logger.info('Attempting a hot restart');

    try {
      await _performWebSocketHotRestart();
      _logger.info('Hot restart completed successfully');
      return {'result': vm_service.Success().toJson()};
    } on NoClientsAvailableException catch (e) {
      // Throw RPC error with kIsolateCannotReload code when no browser clients are
      // connected.
      throw vm_service.RPCError(
        'hotRestart',
        vm_service.RPCErrorKind.kIsolateCannotReload.code,
        'Hot restart failed: ${e.message}',
      );
    } catch (e) {
      _logger.warning('Hot restart failed: $e');
      return {
        'error': {
          'code': vm_service.RPCErrorKind.kInternalError.code,
          'message': 'Hot restart failed: $e',
        },
      };
    }
  }

  /// Completes hot reload with response from client.
  @override
  void completeHotReload(HotReloadResponse response) {
    final tracker = _pendingHotReloads[response.id];

    if (tracker == null) {
      _logger.warning(
        'Received hot reload response but no pending tracker found (id: ${response.id})',
      );
      return;
    }

    tracker.addResponse(response);

    if (tracker.gotAllResponses) {
      _pendingHotReloads.remove(response.id);
      tracker.dispose();

      if (tracker.allSuccessful) {
        tracker.completer.complete(response);
      } else {
        final failedResponses = tracker.responses.where((r) => !r.success);
        final errorMessages = failedResponses
            .map((r) => r.errorMessage ?? 'Unknown error')
            .join('; ');
        tracker.completer.completeError(
          'Hot reload failed in some clients: $errorMessages',
        );
      }
    }
  }

  /// Completes hot restart with response from client.
  @override
  void completeHotRestart(HotRestartResponse response) {
    final tracker = _pendingHotRestarts[response.id];

    if (tracker == null) {
      _logger.warning(
        'Received hot restart response but no pending tracker found (id: ${response.id})',
      );
      return;
    }

    tracker.addResponse(response);

    if (tracker.gotAllResponses) {
      _pendingHotRestarts.remove(response.id);
      tracker.dispose();

      if (tracker.allSuccessful) {
        tracker.completer.complete(response);
      } else {
        final failedResponses = tracker.responses.where((r) => !r.success);
        final errorMessages = failedResponses
            .map((r) => r.errorMessage ?? 'Unknown error')
            .join('; ');
        tracker.completer.completeError(
          'Hot restart failed in some clients: $errorMessages',
        );
      }
    }
  }

  /// Performs WebSocket-based hot reload.
  Future<void> _performWebSocketHotReload({String? requestId}) async {
    final id = requestId ?? createId();

    // Check if there's already a pending hot reload with this ID
    if (_pendingHotReloads.containsKey(id)) {
      throw StateError('Hot reload already pending for ID: $id');
    }

    const timeout = Duration(seconds: 10);
    _logger.info('Sending HotReloadRequest with ID ($id) to client');

    // Send the request and get the number of connected clients
    final clientCount = await Future.microtask(() {
      return sendClientRequest(HotReloadRequest((b) => b.id = id));
    });

    if (clientCount == 0) {
      _logger.warning(kNoClientsAvailable);
      throw NoClientsAvailableException._(kNoClientsAvailable);
    }

    // Create tracker for this hot reload request
    final completer = Completer<HotReloadResponse>();
    final timeoutTimer = Timer(timeout, () {
      final tracker = _pendingHotReloads.remove(id);
      if (tracker != null) {
        tracker.dispose();
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Hot reload timed out - received ${tracker.responses.length}/$clientCount responses',
              timeout,
            ),
          );
        }
      }
    });

    final tracker = _HotReloadTracker(
      requestId: id,
      completer: completer,
      expectedResponses: clientCount,
      timeoutTimer: timeoutTimer,
    );

    _pendingHotReloads[id] = tracker;

    try {
      final response = await completer.future;
      if (!response.success) {
        throw Exception(response.errorMessage ?? 'Client reported failure');
      }
    } catch (e) {
      // Clean up tracker if still present
      final remainingTracker = _pendingHotReloads.remove(id);
      remainingTracker?.dispose();
      rethrow;
    }
  }

  /// Performs WebSocket-based hot restart.
  Future<void> _performWebSocketHotRestart({String? requestId}) async {
    final id = requestId ?? createId();

    // Check if there's already a pending hot restart with this ID
    if (_pendingHotRestarts.containsKey(id)) {
      throw StateError('Hot restart already pending for ID: $id');
    }

    const timeout = Duration(seconds: 15);
    _logger.info('Sending HotRestartRequest with ID ($id) to client');

    // Send the request and get the number of connected clients
    final clientCount = await Future.microtask(() {
      return sendClientRequest(HotRestartRequest((b) => b.id = id));
    });

    if (clientCount == 0) {
      _logger.warning(kNoClientsAvailable);
      throw NoClientsAvailableException._(kNoClientsAvailable);
    }

    // Create tracker for this hot restart request
    final completer = Completer<HotRestartResponse>();
    final timeoutTimer = Timer(timeout, () {
      final tracker = _pendingHotRestarts.remove(id);
      if (tracker != null) {
        tracker.dispose();
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Hot restart timed out - received ${tracker.responses.length}/$clientCount responses',
              timeout,
            ),
          );
        }
      }
    });

    final tracker = _HotRestartTracker(
      requestId: id,
      completer: completer,
      expectedResponses: clientCount,
      timeoutTimer: timeoutTimer,
    );

    _pendingHotRestarts[id] = tracker;

    try {
      final response = await completer.future;
      if (!response.success) {
        throw Exception(response.errorMessage ?? 'Client reported failure');
      }
    } catch (e) {
      // Clean up tracker if still present
      final remainingTracker = _pendingHotRestarts.remove(id);
      remainingTracker?.dispose();
      rethrow;
    }
  }

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map? args,
  }) => wrapInErrorHandlerAsync(
    'callServiceExtension',
    () => _callServiceExtension(method, args: args),
  );

  /// Calls a service extension on the client.
  Future<Response> _callServiceExtension(String method, {Map? args}) async {
    final requestId = createId();

    // Check if there's already a pending service extension with this ID
    if (_pendingServiceExtensionTrackers.containsKey(requestId)) {
      throw StateError(
        'Service extension call already pending for ID: $requestId',
      );
    }

    final request = ServiceExtensionRequest.fromArgs(
      id: requestId,
      method: method,
      args: <String, Object?>{...?args},
    );

    // Send the request and get the number of connected clients
    final clientCount = sendClientRequest(request);

    if (clientCount == 0) {
      throw StateError('No clients available for service extension');
    }

    // Create tracker for this service extension request
    const timeout = Duration(seconds: 10);
    final completer = Completer<ServiceExtensionResponse>();
    final timeoutTimer = Timer(timeout, () {
      final tracker = _pendingServiceExtensionTrackers.remove(requestId);
      if (tracker != null) {
        tracker.dispose();
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException(
              'Service extension $method timed out - received ${tracker.responses.length}/$clientCount responses',
              timeout,
            ),
          );
        }
      }
    });

    final tracker = _ServiceExtensionTracker(
      requestId: requestId,
      completer: completer,
      expectedResponses: clientCount,
      timeoutTimer: timeoutTimer,
    );

    _pendingServiceExtensionTrackers[requestId] = tracker;

    try {
      final response = await completer.future;

      if (response.errorMessage != null) {
        throw RPCError(
          method,
          response.errorCode ?? RPCErrorKind.kServerError.code,
          response.errorMessage!,
        );
      }
      return Response()..json = response.result;
    } catch (e) {
      // Clean up tracker if still present
      final remainingTracker = _pendingServiceExtensionTrackers.remove(
        requestId,
      );
      remainingTracker?.dispose();
      rethrow;
    }
  }

  /// Completes service extension with response.
  @override
  void completeServiceExtension(ServiceExtensionResponse response) {
    final id = response.id;

    final tracker = _pendingServiceExtensionTrackers[id];

    if (tracker == null) {
      _logger.warning(
        'No pending tracker found for service extension (id: $id)',
      );
      return;
    }

    tracker.addResponse(response);

    if (tracker.gotAllResponses) {
      _pendingServiceExtensionTrackers.remove(id);
      tracker.dispose();

      if (tracker.allSuccessful) {
        tracker.completer.complete(response);
      } else {
        final failedResponses = tracker.responses.where((r) => !r.success);
        final errorMessages = failedResponses
            .map((r) => r.errorMessage ?? 'Unknown error')
            .join('; ');
        tracker.completer.completeError(
          'Service extension failed in some clients: $errorMessages',
        );
      }
    }
  }

  /// Parses the [RegisterEvent] and emits a corresponding Dart VM Service
  /// protocol [Event].
  @override
  void parseRegisterEvent(RegisterEvent registerEvent) {
    if (!_isIsolateRunning || _isolateRef == null) {
      _logger.warning('Cannot register service extension - no isolate running');
      return;
    }

    final service = registerEvent.eventData;

    // Emit ServiceExtensionAdded event for tooling
    final event = vm_service.Event(
      kind: vm_service.EventKind.kServiceExtensionAdded,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isolate: _isolateRef!,
    );
    event.extensionRPC = service;

    _streamNotify(vm_service.EventStreams.kIsolate, event);
  }

  /// Parses the [BatchedDebugEvents] and emits corresponding Dart VM Service
  /// protocol [Event]s.
  @override
  void parseBatchedDebugEvents(BatchedDebugEvents debugEvents) {
    for (final debugEvent in debugEvents.events) {
      parseDebugEvent(debugEvent);
    }
  }

  /// Parses the [DebugEvent] and emits a corresponding Dart VM Service
  /// protocol [Event].
  @override
  void parseDebugEvent(DebugEvent debugEvent) {
    if (!_isIsolateRunning || _isolateRef == null) {
      _logger.warning('Cannot parse debug event - no isolate running');
      return;
    }

    _streamNotify(
      vm_service.EventStreams.kExtension,
      vm_service.Event(
          kind: vm_service.EventKind.kExtension,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: _isolateRef!,
        )
        ..extensionKind = debugEvent.kind
        ..extensionData = vm_service.ExtensionData.parse(
          jsonDecode(debugEvent.eventData) as Map<String, dynamic>,
        ),
    );
  }

  @override
  Future<Success> setFlag(String name, String value) =>
      wrapInErrorHandlerAsync('setFlag', () => _setFlag(name, value));

  Future<Success> _setFlag(String name, String value) async {
    if (!currentVmServiceFlags.containsKey(name)) {
      return rpcNotSupportedFuture('setFlag');
    }

    assert(value == 'true' || value == 'false');
    final oldValue = currentVmServiceFlags[name];
    currentVmServiceFlags[name] = value == 'true';

    // Handle pause_isolates_on_start flag changes
    if (name == _pauseIsolatesOnStartFlag &&
        value == 'true' &&
        oldValue == false) {
      // Send pause event for existing isolate if not already paused
      if (_isIsolateRunning &&
          _isolateRef != null &&
          _currentPauseEvent == null) {
        final pauseEvent = vm_service.Event(
          kind: vm_service.EventKind.kPauseStart,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: _isolateRef!,
        );
        _currentPauseEvent = pauseEvent;
        _streamNotify(vm_service.EventStreams.kDebug, pauseEvent);
      }
    }

    return Success();
  }

  @override
  Future<UriList> lookupResolvedPackageUris(
    String isolateId,
    List<String> uris, {
    bool? local,
  }) => wrapInErrorHandlerAsync(
    'lookupResolvedPackageUris',
    () => _lookupResolvedPackageUris(isolateId, uris),
  );

  Future<UriList> _lookupResolvedPackageUris(
    String _,
    List<String> uris,
  ) async {
    await isInitialized;
    return UriList(uris: uris.map(DartUri.toResolvedUri).toList());
  }

  /// Pauses execution of the isolate.
  @override
  Future<Success> pause(String isolateId) =>
      wrapInErrorHandlerAsync('pause', () => _pause(isolateId));

  Future<Success> _pause(String _) async {
    // Create a pause event and store it
    if (_isolateRef != null) {
      final pauseEvent = vm_service.Event(
        kind: vm_service.EventKind.kPauseInterrupted,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isolate: _isolateRef!,
      );
      _currentPauseEvent = pauseEvent;
      _streamNotify(vm_service.EventStreams.kDebug, pauseEvent);
    }

    return Success();
  }

  /// Resumes execution of the isolate.
  @override
  Future<Success> resume(String isolateId, {String? step, int? frameIndex}) =>
      wrapInErrorHandlerAsync('resume', () => _resume(isolateId));

  Future<Success> _resume(String isolateId) async {
    if (hasPendingRestart && !resumeAfterRestartEventsController.isClosed) {
      resumeAfterRestartEventsController.add(isolateId);
    } else {
      if (!_mainHasStarted) {
        try {
          appConnection.runMain();
          _mainHasStarted = true;
        } catch (e) {
          if (e.toString().contains('Main has already started')) {
            _mainHasStarted = true;
          } else {
            rethrow;
          }
        }
      }
    }

    // Clear pause state and send resume event to notify debugging tools
    if (_currentPauseEvent != null && _isolateRef != null) {
      _currentPauseEvent = null;
      final resumeEvent = vm_service.Event(
        kind: vm_service.EventKind.kResume,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isolate: _isolateRef!,
      );
      _streamNotify(vm_service.EventStreams.kDebug, resumeEvent);
    }

    return Success();
  }

  @override
  Future<UriList> lookupPackageUris(String isolateId, List<String> uris) =>
      wrapInErrorHandlerAsync(
        'lookupPackageUris',
        () => _lookupPackageUris(isolateId, uris),
      );

  Future<UriList> _lookupPackageUris(String _, List<String> uris) async {
    await isInitialized;
    return UriList(uris: uris.map(DartUri.toPackageUri).toList());
  }

  @override
  Future<Success> registerService(String service, String alias) {
    return rpcNotSupportedFuture('registerService');
  }

  @override
  Future<FlagList> getFlagList() =>
      wrapInErrorHandlerAsync('getFlagList', _getFlagList);

  Future<FlagList> _getFlagList() async {
    // Return basic flag list for WebSocket mode
    return FlagList(
      flags: [
        Flag(
          name: _pauseIsolatesOnStartFlag,
          comment: 'If enabled, isolates are paused on start',
          valueAsString: pauseIsolatesOnStart.toString(),
        ),
      ],
    );
  }

  @override
  Future<vm_service.Stack> getStack(
    String isolateId, {
    String? idZoneId,
    int? limit,
  }) => wrapInErrorHandlerAsync('getStack', () => _getStack(isolateId));

  Future<vm_service.Stack> _getStack(String isolateId) async {
    if (!_isIsolateRunning || _isolateRef == null) {
      throw vm_service.RPCError(
        'getStack',
        vm_service.RPCErrorKind.kInvalidParams.code,
        'No running isolate found for id: $isolateId',
      );
    }
    if (_isolateRef!.id != isolateId) {
      throw vm_service.RPCError(
        'getStack',
        vm_service.RPCErrorKind.kInvalidParams.code,
        'Isolate with id $isolateId not found.',
      );
    }

    // Return empty stack since we're in WebSocket mode without Chrome debugging
    return vm_service.Stack(
      frames: [],
      asyncCausalFrames: [],
      awaiterFrames: [],
    );
  }
}

/// Extended ReloadReport that includes additional metadata in JSON output.
class _ReloadReportWithMetadata extends vm_service.ReloadReport {
  final List<String>? notices;
  _ReloadReportWithMetadata({super.success, this.notices});

  @override
  Map<String, dynamic> toJson() {
    final jsonified = <String, Object?>{
      'type': 'ReloadReport',
      'success': success ?? false,
    };
    if (notices != null) {
      jsonified['notices'] = notices!.map((e) => {'message': e}).toList();
    }
    return jsonified;
  }
}
