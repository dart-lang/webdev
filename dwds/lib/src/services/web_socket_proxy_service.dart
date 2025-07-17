// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:dwds/data/debug_event.dart';
import 'package:dwds/data/hot_reload_request.dart';
import 'package:dwds/data/hot_reload_response.dart';
import 'package:dwds/data/register_event.dart';
import 'package:dwds/data/service_extension_request.dart';
import 'package:dwds/data/service_extension_response.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service_interface/vm_service_interface.dart';

/// Defines callbacks for sending messages to the connected client.
/// Returns the number of clients the request was successfully sent to.
typedef SendClientRequest = int Function(Object request);

const _pauseIsolatesOnStartFlag = 'pause_isolates_on_start';

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

  bool get isComplete => responses.length >= expectedResponses;

  void addResponse(HotReloadResponse response) {
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

  bool get isComplete => responses.length >= expectedResponses;

  void addResponse(ServiceExtensionResponse response) {
    responses.add(response);
  }

  bool get allSuccessful => responses.every((r) => r.success == true);

  void dispose() {
    timeoutTimer.cancel();
  }
}

/// WebSocket-based VM service proxy for web debugging.
class WebSocketProxyService implements VmServiceInterface {
  final _logger = Logger('WebSocketProxyService');

  /// Signals when the isolate is ready.
  Future<void> get isInitialized => _initializedCompleter.future;
  Completer<void> _initializedCompleter = Completer<void>();

  /// Active service extension trackers by request ID.
  final Map<String, _ServiceExtensionTracker> _pendingServiceExtensionTrackers =
      {};

  /// Sends messages to the client.
  final SendClientRequest sendClientRequest;

  /// App connection for this service.
  AppConnection appConnection;

  /// Active hot reload trackers by request ID.
  final Map<String, _HotReloadTracker> _pendingHotReloads = {};

  /// App connection cleanup subscription.
  StreamSubscription<void>? _appConnectionDoneSubscription;

  /// Event stream controllers.
  final Map<String, StreamController<vm_service.Event>> _streamControllers = {};

  /// VM service runtime flags.
  final Map<String, bool> _currentVmServiceFlags = {
    _pauseIsolatesOnStartFlag: false,
  };

  /// Stream controller for resume events after restart.
  final _resumeAfterRestartEventsController =
      StreamController<String>.broadcast();

  /// Stream of resume events after restart.
  Stream<String> get resumeAfterRestartEventsStream =>
      _resumeAfterRestartEventsController.stream;

  /// Whether there's a pending restart.
  bool get hasPendingRestart => _resumeAfterRestartEventsController.hasListener;

  /// Whether isolates should pause on start.
  bool get pauseIsolatesOnStart =>
      _currentVmServiceFlags[_pauseIsolatesOnStartFlag] ?? false;

  /// Counter for generating unique isolate IDs across page refreshes
  static int _globalIsolateIdCounter = 0;

  bool get _isIsolateRunning => _isolateRunning;

  /// Root VM instance.
  final vm_service.VM _vm;

  WebSocketProxyService._(
    this.sendClientRequest,
    this._vm,
    this.appConnection,
  ); // Isolate state
  vm_service.IsolateRef? _isolateRef;
  bool _isolateRunning = false;
  vm_service.Event? _currentPauseEvent;
  bool _mainHasStarted = false;

  /// Creates a new isolate for WebSocket debugging.
  Future<void> createIsolate([AppConnection? appConnectionOverride]) async {
    // Update app connection if override provided
    appConnection = appConnectionOverride ?? appConnection;

    // Auto-cleanup on connection close
    await _appConnectionDoneSubscription?.cancel();
    _appConnectionDoneSubscription = appConnection.onDone.asStream().listen((
      _,
    ) {
      destroyIsolate();
    });

    // Create isolate reference with unique ID that changes on each page refresh
    final isolateId = '${++_globalIsolateIdCounter}';
    final isolateRef = vm_service.IsolateRef(
      id: isolateId,
      name: 'main()',
      number: isolateId,
      isSystemIsolate: false,
    );

    _isolateRef = isolateRef;
    _isolateRunning = true;
    _vm.isolates?.add(isolateRef);
    final timestamp = DateTime.now().millisecondsSinceEpoch;

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
    if (!_initializedCompleter.isCompleted) _initializedCompleter.complete();
  }

  /// Destroys the isolate and cleans up state.
  void destroyIsolate() {
    _logger.fine('Destroying isolate');
    if (!_isIsolateRunning) return;

    final isolateRef = _isolateRef;

    _appConnectionDoneSubscription?.cancel();
    _appConnectionDoneSubscription = null;

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

    _vm.isolates?.removeWhere((ref) => ref.id == isolateRef?.id);

    // Reset state
    _isolateRef = null;
    _isolateRunning = false;
    _currentPauseEvent = null;
    _mainHasStarted = false;

    if (_initializedCompleter.isCompleted) {
      _initializedCompleter = Completer<void>();
    }
  }

  /// Sends events to stream controllers.
  void _streamNotify(String streamId, vm_service.Event event) {
    final controller = _streamControllers[streamId];
    if (controller == null) return;
    controller.add(event);
  }

  @override
  Future<Success> setLibraryDebuggable(
    String isolateId,
    String libraryId,
    bool isDebuggable,
  ) {
    return _rpcNotSupportedFuture('setLibraryDebuggable');
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

  static Future<T> _rpcNotSupportedFuture<T>(String method) {
    return Future.error(_rpcNotSupported(method));
  }

  static RPCError _rpcNotSupported(String method) {
    return RPCError(
      method,
      RPCErrorKind.kMethodNotFound.code,
      '$method: Not supported on web devices',
    );
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

  /// Returns a broadcast stream for the given streamId.
  @override
  Stream<vm_service.Event> onEvent(String streamId) {
    return _streamControllers.putIfAbsent(streamId, () {
      switch (streamId) {
        case vm_service.EventStreams.kExtension:
        case vm_service.EventStreams.kIsolate:
        case vm_service.EventStreams.kVM:
        case vm_service.EventStreams.kGC:
        case vm_service.EventStreams.kTimeline:
        case vm_service.EventStreams.kService:
        case vm_service.EventStreams.kDebug:
        case vm_service.EventStreams.kLogging:
        case vm_service.EventStreams.kStdout:
        case vm_service.EventStreams.kStderr:
          return StreamController<vm_service.Event>.broadcast();
        default:
          _logger.warning('Unsupported stream: $streamId');
          throw vm_service.RPCError(
            'streamListen',
            vm_service.RPCErrorKind.kInvalidParams.code,
            'Stream `$streamId` not supported on web devices',
          );
      }
    }).stream;
  }

  @override
  Future<vm_service.Success> streamListen(String streamId) =>
      wrapInErrorHandlerAsync('streamListen', () => _streamListen(streamId));

  Future<vm_service.Success> _streamListen(String streamId) async {
    onEvent(streamId);
    return vm_service.Success();
  }

  /// Adds events to stream controllers.
  void addEvent(String streamId, vm_service.Event event) {
    final controller = _streamControllers[streamId];
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
      return _vm;
    }, (result) => DwdsEvent.getVM());
  }

  /// Not available in WebSocket mode.
  dynamic get remoteDebugger {
    throw UnsupportedError(
      'remoteDebugger not available in WebSocketProxyService.\n'
      'Called from:\n${StackTrace.current}',
    );
  }

  /// Returns supported VM service protocols.
  @override
  Future<vm_service.ProtocolList> getSupportedProtocols() async {
    final version = semver.Version.parse(vm_service.vmServiceVersion);
    return vm_service.ProtocolList(
      protocols: [
        vm_service.Protocol(
          protocolName: 'VM Service',
          major: version.major,
          minor: version.minor,
        ),
      ],
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
    } catch (e) {
      _logger.warning('Hot reload failed: $e');
      return _ReloadReportWithMetadata(success: false, notices: [e.toString()]);
    }
  }

  /// Completes hot reload with response from client.
  void completeHotReload(HotReloadResponse response) {
    final tracker = _pendingHotReloads[response.id];

    if (tracker == null) {
      _logger.warning(
        'Received hot reload response but no pending tracker found (id: ${response.id})',
      );
      return;
    }

    tracker.addResponse(response);

    if (tracker.isComplete) {
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
      throw StateError('No clients available for hot reload');
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

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map? args,
  }) => wrapInErrorHandlerAsync(
    'callServiceExtension',
    () => _callServiceExtension(method, isolateId: isolateId, args: args),
  );

  /// Calls a service extension on the client.
  Future<Response> _callServiceExtension(
    String method, {
    String? isolateId,
    Map? args,
  }) async {
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
      args:
          args != null ? Map<String, dynamic>.from(args) : <String, dynamic>{},
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

    if (tracker.isComplete) {
      _pendingServiceExtensionTrackers.remove(id);
      tracker.dispose();

      if (tracker.allSuccessful) {
        tracker.completer.complete(response);
      } else {
        final failedResponses = tracker.responses.where(
          (r) => r.success != true,
        );
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
  void parseBatchedDebugEvents(BatchedDebugEvents debugEvents) {
    for (final debugEvent in debugEvents.events) {
      parseDebugEvent(debugEvent);
    }
  }

  /// Parses the [DebugEvent] and emits a corresponding Dart VM Service
  /// protocol [Event].
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
    if (!_currentVmServiceFlags.containsKey(name)) {
      return _rpcNotSupportedFuture('setFlag');
    }

    assert(value == 'true' || value == 'false');
    final oldValue = _currentVmServiceFlags[name];
    _currentVmServiceFlags[name] = value == 'true';

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
    String isolateId,
    List<String> uris,
  ) async {
    await isInitialized;
    return UriList(uris: uris.map(DartUri.toResolvedUri).toList());
  }

  /// Pauses execution of the isolate.
  @override
  Future<Success> pause(String isolateId) =>
      wrapInErrorHandlerAsync('pause', () => _pause(isolateId));

  Future<Success> _pause(String isolateId) async {
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
      wrapInErrorHandlerAsync(
        'resume',
        () => _resume(isolateId, step: step, frameIndex: frameIndex),
      );

  Future<Success> _resume(
    String isolateId, {
    String? step,
    int? frameIndex,
  }) async {
    if (hasPendingRestart && !_resumeAfterRestartEventsController.isClosed) {
      _resumeAfterRestartEventsController.add(isolateId);
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

  Future<UriList> _lookupPackageUris(
    String isolateId,
    List<String> uris,
  ) async {
    await isInitialized;
    return UriList(uris: uris.map(DartUri.toPackageUri).toList());
  }

  @override
  Future<Success> registerService(String service, String alias) {
    return _rpcNotSupportedFuture('registerService');
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
  }) => wrapInErrorHandlerAsync(
    'getStack',
    () => _getStack(isolateId, idZoneId: idZoneId, limit: limit),
  );

  Future<vm_service.Stack> _getStack(
    String isolateId, {
    String? idZoneId,
    int? limit,
  }) async {
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
