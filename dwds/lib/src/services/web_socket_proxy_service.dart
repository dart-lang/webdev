// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds/data/hot_reload_request.dart';
import 'package:dwds/data/hot_reload_response.dart';
import 'package:dwds/data/service_extension_request.dart';
import 'package:dwds/data/service_extension_response.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:logging/logging.dart';
// Ensure RPCError and RPCErrorKind are available for error handling
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service.dart';
import 'package:vm_service_interface/vm_service_interface.dart';

/// Defines callbacks for sending messages to the connected client.
typedef SendClientRequest = void Function(Object request);

const _pauseIsolatesOnStartFlag = 'pause_isolates_on_start';

/// WebSocket-based VM service proxy for web debugging.
///
/// Provides hot reload and service extension support via WebSocket communication.
class WebSocketProxyService implements VmServiceInterface {
  final _logger = Logger('WebSocketProxyService');

  /// Signals when the isolate is ready.
  Future<void> get isInitialized => _initializedCompleter.future;
  Completer<void> _initializedCompleter = Completer<void>();

  /// Active service extension requests by ID.
  final Map<String, Completer<ServiceExtensionResponse>>
  _pendingServiceExtensions = {};

  /// Sends messages to the client.
  final SendClientRequest sendClientRequest;

  /// App connection for this service.
  final AppConnection appConnection;

  /// Current hot reload request (one at a time).
  Completer<HotReloadResponse>? _pendingHotReload;

  /// App connection cleanup subscription.
  StreamSubscription<void>? _appConnectionDoneSubscription;

  /// Event stream controllers.
  final Map<String, StreamController<vm_service.Event>> _streamControllers = {};

  /// VM service runtime flags.
  final Map<String, bool> _currentVmServiceFlags = {
    _pauseIsolatesOnStartFlag: false,
  };

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
  bool _hasResumed = false;

  bool get _isIsolateRunning => _isolateRunning;

  /// Creates a new isolate for WebSocket debugging.
  ///
  /// Destroys existing isolate first if present. Call [destroyIsolate] on restart.
  Future<void> createIsolate([AppConnection? appConnectionOverride]) async {
    final appConn = appConnectionOverride ?? appConnection;

    // Clean up existing isolate
    if (_isIsolateRunning) {
      destroyIsolate();
      await Future.delayed(Duration(milliseconds: 10));
    }

    // Auto-cleanup on connection close
    await _appConnectionDoneSubscription?.cancel();
    _appConnectionDoneSubscription = appConn.onDone.asStream().listen((_) {
      destroyIsolate();
    });

    // Create isolate reference
    final isolateRef = vm_service.IsolateRef(
      id: '1',
      name: 'main()',
      number: '1',
      isSystemIsolate: false,
    );

    _isolateRef = isolateRef;
    _isolateRunning = true;
    _hasResumed = false;
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

    if (!_initializedCompleter.isCompleted) _initializedCompleter.complete();

    // Set up appConnection.onStart listener (like Chrome flow does)
    appConn.onStart.then((_) {
      // Unlike Chrome flow, we don't have debugger.resumeFromStart(), but we can trigger resume
      if (pauseIsolatesOnStart && !_hasResumed) {
        final resumeEvent = vm_service.Event(
          kind: vm_service.EventKind.kResume,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: isolateRef,
        );
        _hasResumed = true;
        _streamNotify(vm_service.EventStreams.kDebug, resumeEvent);
      }
    });

    // Send pause event if enabled
    if (pauseIsolatesOnStart) {
      final pauseEvent = vm_service.Event(
        kind: vm_service.EventKind.kPauseStart,
        timestamp: timestamp,
        isolate: isolateRef,
      );
      _currentPauseEvent = pauseEvent;
      _hasResumed = false;
      _streamNotify(vm_service.EventStreams.kDebug, pauseEvent);
      // Flutter tools will call resume() to start the app

      // Auto-resume after a short delay if no debugger is connected
      // This handles the case where the app is run from terminal without debug extension
      _scheduleAutoResumeIfNeeded();
    } else {
      // If we're not pausing on start, immediately send a resume event
      // to ensure the app knows it can start running
      _logger.info('Not pausing on start, sending immediate resume event');
      final resumeEvent = vm_service.Event(
        kind: vm_service.EventKind.kResume,
        timestamp: timestamp,
        isolate: isolateRef,
      );
      _hasResumed = true;
      _streamNotify(vm_service.EventStreams.kDebug, resumeEvent);
    }
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
    _hasResumed = false;

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

  /// Returns a broadcast stream for the given streamId, creating if needed.
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
      _logger.fine('Added event to stream $streamId: $event');
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
    // On web, we do not currently support isolates, so isInitialized is not required.
    return captureElapsedTime(() async {
      return _vm;
    }, (result) => DwdsEvent.getVM());
  }

  /// Throws error if remoteDebugger is accessed (not available in WebSocket mode).
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

  /// Completes hot reload with response.
  void completeHotReload(HotReloadResponse response) {
    final completer = _pendingHotReload;
    _pendingHotReload = null;

    if (completer != null) {
      if (response.success) {
        completer.complete(response);
      } else {
        completer.completeError(
          response.errorMessage ?? 'Unknown client error during hot reload',
        );
      }
    } else {
      _logger.warning(
        'Received hot reload response but no pending completer found (id: ${response.id})',
      );
    }
  }

  /// Performs WebSocket-based hot reload.
  Future<void> _performWebSocketHotReload({String? requestId}) async {
    if (_pendingHotReload != null) {
      throw StateError('Hot reload already pending');
    }

    final id = requestId ?? createId();
    final completer = Completer<HotReloadResponse>();
    _pendingHotReload = completer;

    const timeout = Duration(seconds: 10);
    _logger.info('Sending HotReloadRequest with ID ($id) to client');

    await Future.microtask(() {
      sendClientRequest(HotReloadRequest((b) => b.id = id));
    });

    try {
      final response = await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingHotReload = null;
          throw TimeoutException(
            'Client did not respond to hot reload',
            timeout,
          );
        },
      );

      if (!response.success) {
        throw Exception(response.errorMessage ?? 'Client reported failure');
      }
    } catch (e) {
      _pendingHotReload = null;
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
    if (_pendingServiceExtensions.containsKey(requestId)) {
      throw StateError('Service extension call already pending for this ID');
    }

    final completer = Completer<ServiceExtensionResponse>();
    _pendingServiceExtensions[requestId] = completer;

    final request = ServiceExtensionRequest.fromArgs(
      id: requestId,
      method: method,
      args:
          args != null ? Map<String, dynamic>.from(args) : <String, dynamic>{},
    );
    sendClientRequest(request);

    final response = await completer.future.timeout(Duration(seconds: 10));
    _pendingServiceExtensions.remove(requestId);

    if (response.errorMessage != null) {
      throw RPCError(
        method,
        response.errorCode ?? RPCErrorKind.kServerError.code,
        response.errorMessage!,
      );
    }
    return Response()..json = response.result;
  }

  /// Completes service extension with response.
  void completeServiceExtension(ServiceExtensionResponse response) {
    final id = response.id;
    final completer = _pendingServiceExtensions.remove(id);

    if (completer != null) {
      if (response.success == true) {
        completer.complete(response);
      } else {
        completer.completeError(
          response.errorMessage ??
              'Unknown client error during service extension',
        );
      }
    } else {
      _logger.warning(
        'No pending completer found for service extension (id: $id)',
      );
    }
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

    // Handle pause_isolates_on_start flag
    if (name == _pauseIsolatesOnStartFlag &&
        value == 'true' &&
        oldValue == false) {
      // Send pause event for existing isolate if it wasn't paused initially
      if (_isIsolateRunning &&
          _isolateRef != null &&
          _currentPauseEvent == null) {
        final pauseEvent = vm_service.Event(
          kind: vm_service.EventKind.kPauseStart,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isolate: _isolateRef!,
        );
        _currentPauseEvent = pauseEvent;
        _hasResumed = false;
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
    // Check if we should trigger runMain instead
    if (!_hasResumed && _currentPauseEvent != null) {
      appConnection.runMain();
    }
    
    // Prevent multiple resume calls
    if (_hasResumed && _currentPauseEvent == null) {
      return Success();
    }

    _currentPauseEvent = null;
    _hasResumed = true;

    // Send resume event
    if (_isolateRef != null) {
      final resumeEvent = vm_service.Event(
        kind: vm_service.EventKind.kResume,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        isolate: _isolateRef!,
      );

      _streamNotify(vm_service.EventStreams.kDebug, resumeEvent);
      _logger.fine('Sent resume event for isolate ${_isolateRef!.id}');
    }

    // Handle restart events
    if (_resumeAfterRestartEventsController.hasListener) {
      _resumeAfterRestartEventsController.add(isolateId);
      return Success();
    }

    return Success();
  }

  /// Schedules an auto-resume if no debugger connection is detected.
  /// This prevents the app from being stuck in a paused state when running from terminal.
  void _scheduleAutoResumeIfNeeded() {
    _logger.info('Scheduling auto-resume check in 2 seconds');
    // Wait a reasonable amount of time for a debugger to connect
    Timer(Duration(seconds: 2), () {
      // If we're still paused and no debugger has taken control, auto-resume
      if (_currentPauseEvent != null &&
          _currentPauseEvent!.kind == vm_service.EventKind.kPauseStart &&
          !_hasResumed) {
        _logger.info(
          'Auto-resuming isolate after timeout (no debugger connected)',
        );
        // Auto-resume the isolate
        safeUnawaited(_resume(_isolateRef?.id ?? '1'));
      } else {
        _logger.info(
          'Auto-resume check: isolate already resumed or no pause event',
        );
      }
    });
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
