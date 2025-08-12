// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds/data/debug_event.dart';
import 'package:dwds/data/hot_reload_response.dart';
import 'package:dwds/data/hot_restart_response.dart';
import 'package:dwds/data/register_event.dart';
import 'package:dwds/data/service_extension_response.dart';
import 'package:dwds/src/connections/app_connection.dart';
import 'package:dwds/src/events.dart';
import 'package:dwds/src/utilities/shared.dart';
import 'package:pub_semver/pub_semver.dart' as semver;
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service_interface/vm_service_interface.dart';

const pauseIsolatesOnStartFlag = 'pause_isolates_on_start';

/// Abstract base class for VM service proxy implementations.
abstract class ProxyService implements VmServiceInterface {
  /// Cache of all existing StreamControllers.
  ///
  /// These are all created through [onEvent].
  final Map<String, StreamController<vm_service.Event>> _streamControllers = {};

  /// The root `VM` instance.
  final vm_service.VM _vm;

  /// Signals when isolate is initialized.
  Future<void> get isInitialized => initializedCompleter.future;
  Completer<void> initializedCompleter = Completer<void>();

  /// The flags that can be set at runtime via [setFlag] and their respective
  /// values.
  final Map<String, bool> _currentVmServiceFlags = {
    pauseIsolatesOnStartFlag: false,
  };

  /// The value of the [pauseIsolatesOnStartFlag].
  ///
  /// This value can be updated at runtime via [setFlag].
  bool get pauseIsolatesOnStart =>
      _currentVmServiceFlags[pauseIsolatesOnStartFlag] ?? false;

  /// Stream controller for resume events after restart.
  final _resumeAfterRestartEventsController =
      StreamController<String>.broadcast();

  /// A global stream of resume events for hot restart.
  ///
  /// The values in the stream are the isolates IDs for the resume event.
  ///
  /// IMPORTANT: This should only be listened to during a hot-restart or page
  /// refresh. The debugger ignores any resume events as long as there is a
  /// subscriber to this stream.
  Stream<String> get resumeAfterRestartEventsStream =>
      _resumeAfterRestartEventsController.stream;

  /// Whether or not the connected app has a pending restart.
  bool get hasPendingRestart => _resumeAfterRestartEventsController.hasListener;

  // Protected accessors for subclasses
  vm_service.VM get vm => _vm;
  Map<String, StreamController<vm_service.Event>> get streamControllers =>
      _streamControllers;
  StreamController<String> get resumeAfterRestartEventsController =>
      _resumeAfterRestartEventsController;
  Map<String, bool> get currentVmServiceFlags => _currentVmServiceFlags;

  ProxyService(this._vm);

  /// Sends events to stream controllers.
  void streamNotify(String streamId, vm_service.Event event) {
    final controller = _streamControllers[streamId];
    if (controller == null) return;
    controller.add(event);
  }

  /// Returns a broadcast stream for the given streamId.
  @override
  Stream<vm_service.Event> onEvent(String streamId) {
    return _streamControllers.putIfAbsent(streamId, () {
      return StreamController<vm_service.Event>.broadcast();
    }).stream;
  }

  @override
  Future<vm_service.Success> streamListen(String streamId) =>
      wrapInErrorHandlerAsync('streamListen', () => _streamListen(streamId));

  Future<vm_service.Success> _streamListen(String streamId) async {
    onEvent(streamId);
    return vm_service.Success();
  }

  @override
  Future<vm_service.Success> streamCancel(String streamId) {
    // TODO: We should implement this (as we've already implemented
    // streamListen).
    return _rpcNotSupportedFuture('streamCancel');
  }

  @override
  Future<vm_service.VM> getVM() => wrapInErrorHandlerAsync('getVM', _getVM);

  Future<vm_service.VM> _getVM() {
    return captureElapsedTime(() async {
      return _vm;
    }, (result) => DwdsEvent.getVM());
  }

  @override
  Future<vm_service.FlagList> getFlagList() =>
      wrapInErrorHandlerAsync('getFlagList', _getFlagList);

  Future<vm_service.FlagList> _getFlagList() async {
    final flags = _currentVmServiceFlags.entries.map<vm_service.Flag>(
      (entry) =>
          vm_service.Flag(name: entry.key, valueAsString: '${entry.value}'),
    );
    return vm_service.FlagList(flags: flags.toList());
  }

  @override
  Future<vm_service.Success> setFlag(String name, String value) =>
      wrapInErrorHandlerAsync('setFlag', () => _setFlag(name, value));

  Future<vm_service.Success> _setFlag(String name, String value) async {
    if (!_currentVmServiceFlags.containsKey(name)) {
      throw vm_service.RPCError(
        'setFlag',
        vm_service.RPCErrorKind.kInvalidRequest.code,
        'Cannot set flag "$name" (invalid flag)',
      );
    }

    assert(value == 'true' || value == 'false');
    _currentVmServiceFlags[name] = value == 'true';
    return vm_service.Success();
  }

  @override
  Future<vm_service.ProtocolList> getSupportedProtocols() =>
      wrapInErrorHandlerAsync('getSupportedProtocols', _getSupportedProtocols);

  Future<vm_service.ProtocolList> _getSupportedProtocols() async {
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
  Future<vm_service.Version> getVersion() =>
      wrapInErrorHandlerAsync('getVersion', _getVersion);

  Future<vm_service.Version> _getVersion() async {
    final version = semver.Version.parse(vm_service.vmServiceVersion);
    return vm_service.Version(major: version.major, minor: version.minor);
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
  void parseDebugEvent(DebugEvent debugEvent);

  /// Parses the [RegisterEvent] and emits a corresponding Dart VM Service
  /// protocol [Event].
  void parseRegisterEvent(RegisterEvent registerEvent);

  /// Completes hot reload with response from client.
  ///
  /// Default implementation throws [UnimplementedError].
  /// Override in subclasses that support hot reload completion.
  void completeHotReload(HotReloadResponse response) {
    throw UnimplementedError('completeHotReload not supported');
  }

  /// Completes hot restart with response from client.
  ///
  /// Default implementation throws [UnimplementedError].
  /// Override in subclasses that support hot restart completion.
  void completeHotRestart(HotRestartResponse response) {
    throw UnimplementedError('completeHotRestart not supported');
  }

  /// Completes service extension with response from client.
  ///
  /// Default implementation throws [UnimplementedError].
  /// Override in subclasses that support service extension completion.
  void completeServiceExtension(ServiceExtensionResponse response) {
    throw UnimplementedError('completeServiceExtension not supported');
  }

  /// Standard RPC error for unsupported methods.
  static vm_service.RPCError _rpcNotSupported(String method) {
    return vm_service.RPCError(
      method,
      vm_service.RPCErrorKind.kMethodNotFound.code,
      '$method: Not supported on web devices',
    );
  }

  /// Standard future error for unsupported methods.
  static Future<T> _rpcNotSupportedFuture<T>(String method) {
    return Future.error(_rpcNotSupported(method));
  }

  /// Protected accessor for _rpcNotSupportedFuture for subclasses
  Future<T> rpcNotSupportedFuture<T>(String method) {
    return _rpcNotSupportedFuture<T>(method);
  }

  // Default implementations for unsupported methods
  @override
  Future<vm_service.AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) {
    return _rpcNotSupportedFuture('getAllocationProfile');
  }

  @override
  Future<vm_service.ClassList> getClassList(String isolateId) {
    return _rpcNotSupportedFuture('getClassList');
  }

  @override
  Future<vm_service.InstanceSet> getInstances(
    String isolateId,
    String classId,
    int limit, {
    bool? includeImplementers,
    bool? includeSubclasses,
    String? idZoneId,
  }) {
    return _rpcNotSupportedFuture('getInstances');
  }

  @override
  Future<vm_service.Success> kill(String isolateId) {
    return _rpcNotSupportedFuture('kill');
  }

  @override
  Future<vm_service.Success> clearVMTimeline() {
    return _rpcNotSupportedFuture('clearVMTimeline');
  }

  @override
  Future<vm_service.Timeline> getVMTimeline({
    int? timeOriginMicros,
    int? timeExtentMicros,
  }) {
    return _rpcNotSupportedFuture('getVMTimeline');
  }

  @override
  Future<vm_service.TimelineFlags> getVMTimelineFlags() {
    return _rpcNotSupportedFuture('getVMTimelineFlags');
  }

  @override
  Future<vm_service.Success> setVMTimelineFlags(List<String> recordedStreams) {
    return _rpcNotSupportedFuture('setVMTimelineFlags');
  }

  @override
  Future<vm_service.Timestamp> getVMTimelineMicros() {
    return _rpcNotSupportedFuture('getVMTimelineMicros');
  }

  @override
  Future<vm_service.InboundReferences> getInboundReferences(
    String isolateId,
    String targetId,
    int limit, {
    String? idZoneId,
  }) {
    return _rpcNotSupportedFuture('getInboundReferences');
  }

  @override
  Future<vm_service.RetainingPath> getRetainingPath(
    String isolateId,
    String targetId,
    int limit, {
    String? idZoneId,
  }) {
    return _rpcNotSupportedFuture('getRetainingPath');
  }

  @override
  Future<vm_service.Success> requestHeapSnapshot(String isolateId) {
    return _rpcNotSupportedFuture('requestHeapSnapshot');
  }

  @override
  Future<vm_service.IsolateGroup> getIsolateGroup(String isolateGroupId) {
    return _rpcNotSupportedFuture('getIsolateGroup');
  }

  @override
  Future<vm_service.MemoryUsage> getIsolateGroupMemoryUsage(
    String isolateGroupId,
  ) {
    return _rpcNotSupportedFuture('getIsolateGroupMemoryUsage');
  }

  @override
  Future<vm_service.ProcessMemoryUsage> getProcessMemoryUsage() =>
      _rpcNotSupportedFuture('getProcessMemoryUsage');

  @override
  Future<vm_service.PortList> getPorts(String isolateId) =>
      throw UnimplementedError();

  @override
  Future<vm_service.CpuSamples> getAllocationTraces(
    String isolateId, {
    int? timeOriginMicros,
    int? timeExtentMicros,
    String? classId,
  }) => throw UnimplementedError();

  @override
  Future<vm_service.Success> setTraceClassAllocation(
    String isolateId,
    String classId,
    bool enable,
  ) => throw UnimplementedError();

  @override
  Future<vm_service.Breakpoint> setBreakpointState(
    String isolateId,
    String breakpointId,
    bool enable,
  ) => throw UnimplementedError();

  @override
  Future<vm_service.Success> streamCpuSamplesWithUserTag(
    List<String> userTags,
  ) => _rpcNotSupportedFuture('streamCpuSamplesWithUserTag');

  @override
  Future<vm_service.CpuSamples> getCpuSamples(
    String isolateId,
    int timeOriginMicros,
    int timeExtentMicros,
  ) {
    return _rpcNotSupportedFuture('getCpuSamples');
  }

  @override
  Future<vm_service.Success> clearCpuSamples(String isolateId) {
    return _rpcNotSupportedFuture('clearCpuSamples');
  }

  /// Creates a new isolate for debugging.
  ///
  /// Implementations should handle isolate lifecycle management according to
  /// their specific debugging mode (Chrome vs WebSocket).
  Future<void> createIsolate(
    AppConnection appConnection, {
    bool newConnection = false,
  });

  /// Destroys the isolate and cleans up debugging state.
  ///
  /// Implementations should handle cleanup according to their specific
  /// debugging mode and connection management strategy.
  void destroyIsolate();

  /// Prevent DWDS from blocking Dart SDK rolls if changes in package:vm_service
  /// are unimplemented in DWDS.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
