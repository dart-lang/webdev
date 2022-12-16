// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debug_session;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:built_collection/built_collection.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:dwds/data/debug_info.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/src/sockets.dart';
// TODO(https://github.com/dart-lang/sdk/issues/49973): Use conditional imports
// in .../utilities/batched_stream so that we don't need to import a copy.
import 'package:dwds/src/web_utilities/batched_stream.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;
import 'package:sse/client/sse_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'chrome_api.dart';
import 'data_serializers.dart';
import 'data_types.dart';
import 'logger.dart';
import 'storage.dart';
import 'utils.dart';
import 'web_api.dart';
import 'messaging.dart';

const _notADartAppAlert = 'No Dart application detected.'
    ' Are you trying to debug an application that includes a Chrome hosted app'
    ' (an application listed in chrome://apps)? If so, debugging is disabled.'
    ' You can fix this by removing the application from chrome://apps. Please'
    ' see https://bugs.chromium.org/p/chromium/issues/detail?id=885025#c11.';

const _devToolsAlreadyOpenedAlert =
    'DevTools is already opened on a different window.';

final _debugSessions = <_DebugSession>[];
final _tabIdToTrigger = <int, Trigger>{};

enum DetachReason {
  canceled_by_user,
  connection_error_event,
  connection_done_event,
  devtools_tab_closed,
  navigated_away_from_app,
  unknown;

  factory DetachReason.fromString(String value) {
    return DetachReason.values.byName(value);
  }
}

enum ConnectFailureReason {
  authentication,
  no_dart_app,
  timeout,
  unknown;

  factory ConnectFailureReason.fromString(String value) {
    return ConnectFailureReason.values.byName(value);
  }
}

enum TabType {
  dartApp,
  devTools,
}

enum Trigger {
  extensionPanel,
  extensionIcon,
}

void attachDebugger(int dartAppTabId, {required Trigger trigger}) {
  _tabIdToTrigger[dartAppTabId] = trigger;
  _registerDebugEventListeners();
  chrome.debugger.attach(
    Debuggee(tabId: dartAppTabId),
    '1.3',
    allowInterop(
      () => _enableExecutionContextReporting(dartAppTabId),
    ),
  );
}

void detachDebugger(
  int tabId, {
  required TabType type,
  required DetachReason reason,
}) async {
  final debugSession = _debugSessionForTab(tabId, type: type);
  if (debugSession == null) return;
  final debuggee = Debuggee(tabId: debugSession.appTabId);
  final detachPromise = chrome.debugger.detach(debuggee);
  await promiseToFuture(detachPromise);
  final error = chrome.runtime.lastError;
  if (error != null) {
    debugWarn(
        'Error detaching tab for reason: $reason. Error: ${error.message}');
  } else {
    _handleDebuggerDetach(debuggee, reason);
  }
}

void _registerDebugEventListeners() {
  chrome.debugger.onEvent.addListener(allowInterop(_onDebuggerEvent));
  chrome.debugger.onDetach.addListener(allowInterop(
    (source, _) => _handleDebuggerDetach(
      source,
      DetachReason.canceled_by_user,
    ),
  ));
  chrome.tabs.onRemoved.addListener(allowInterop(
    (tabId, _) => detachDebugger(
      tabId,
      type: TabType.devTools,
      reason: DetachReason.devtools_tab_closed,
    ),
  ));
}

_enableExecutionContextReporting(int tabId) {
  // Runtime.enable enables reporting of execution contexts creation by means of
  // executionContextCreated event. When the reporting gets enabled the event
  // will be sent immediately for each existing execution context:
  chrome.debugger.sendCommand(
      Debuggee(tabId: tabId), 'Runtime.enable', EmptyParam(), allowInterop((_) {
    final chromeError = chrome.runtime.lastError;
    if (chromeError != null) {
      final errorMessage = _translateChromeError(chromeError.message);
      chrome.notifications.create(/*notificationId*/ null,
          NotificationOptions(message: errorMessage), /*callback*/ null);
      return;
    }
  }));
}

String _translateChromeError(String chromeErrorMessage) {
  if (chromeErrorMessage.contains('Cannot access') ||
      chromeErrorMessage.contains('Cannot attach')) {
    return _notADartAppAlert;
  }
  return _devToolsAlreadyOpenedAlert;
}

Future<void> _onDebuggerEvent(
    Debuggee source, String method, Object? params) async {
  if (method == 'Runtime.executionContextCreated') {
    return _maybeConnectToDwds(source.tabId, params);
  }

  return _forwardChromeDebuggerEventToDwds(source, method, params);
}

Future<void> _maybeConnectToDwds(int tabId, Object? params) async {
  final context = json.decode(JSON.stringify(params))['context'];
  final contextOrigin = context['origin'] as String?;
  if (contextOrigin == null) return;
  if (contextOrigin.contains(('chrome-extension:'))) return;
  final debugInfo = await fetchStorageObject<DebugInfo>(
    type: StorageObject.debugInfo,
    tabId: tabId,
  );
  if (debugInfo == null) return;
  if (contextOrigin != debugInfo.appOrigin) return;
  final contextId = context['id'] as int;
  final connected = await _connectToDwds(
    dartAppContextId: contextId,
    dartAppTabId: tabId,
    debugInfo: debugInfo,
  );
  if (!connected) {
    debugWarn('Failed to connect to DWDS for $contextOrigin.');
    sendConnectFailureMessage(ConnectFailureReason.unknown,
        dartAppTabId: tabId);
  }
}

Future<bool> _connectToDwds({
  required int dartAppContextId,
  required int dartAppTabId,
  required DebugInfo debugInfo,
}) async {
  if (debugInfo.extensionUrl == null) {
    debugWarn('Can\'t connect to DWDS without an extension URL.');
    return false;
  }
  final uri = Uri.parse(debugInfo.extensionUrl!);
  // Start the client connection with DWDS:
  final client = uri.isScheme('ws') || uri.isScheme('wss')
      ? WebSocketClient(WebSocketChannel.connect(uri))
      : SseSocketClient(SseClient(uri.toString()));
  final trigger = _tabIdToTrigger[dartAppTabId];
  final debugSession = _DebugSession(
    client: client,
    appTabId: dartAppTabId,
    trigger: trigger,
    onIncoming: (data) => _routeDwdsEvent(data, client, dartAppTabId),
    onDone: () {
      detachDebugger(
        dartAppTabId,
        type: TabType.dartApp,
        reason: DetachReason.connection_done_event,
      );
    },
    onError: (err) {
      debugWarn('Connection error: $err', verbose: true);
      detachDebugger(
        dartAppTabId,
        type: TabType.dartApp,
        reason: DetachReason.connection_error_event,
      );
    },
    cancelOnError: true,
  );
  _debugSessions.add(debugSession);
  final tabUrl = await _getTabUrl(dartAppTabId);
  // Send a DevtoolsRequest to the event stream:
  debugSession.sendEvent(DevToolsRequest((b) => b
    ..appId = debugInfo.appId
    ..instanceId = debugInfo.appInstanceId
    ..contextId = dartAppContextId
    ..tabUrl = tabUrl
    ..uriOnly = true));
  return true;
}

void _routeDwdsEvent(String eventData, SocketClient client, int tabId) {
  final message = serializers.deserialize(jsonDecode(eventData));
  if (message is ExtensionRequest) {
    _forwardDwdsEventToChromeDebugger(message, client, tabId);
  } else if (message is ExtensionEvent) {
    switch (message.method) {
      case 'dwds.encodedUri':
        // TODO(elliette): Forward to external extensions.
        break;
      case 'dwds.devtoolsUri':
        _openDevTools(message.params, dartAppTabId: tabId);
        break;
    }
  }
}

void _forwardDwdsEventToChromeDebugger(
    ExtensionRequest message, SocketClient client, int tabId) {
  final messageParams = message.commandParams ?? '{}';
  final params = BuiltMap<String, Object>(json.decode(messageParams)).toMap();
  chrome.debugger.sendCommand(
      Debuggee(tabId: tabId), message.command, js_util.jsify(params),
      allowInterop(([e]) {
    // No arguments indicate that an error occurred.
    if (e == null) {
      client.sink
          .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
            ..id = message.id
            ..success = false
            ..result = JSON.stringify(chrome.runtime.lastError)))));
    } else {
      client.sink
          .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
            ..id = message.id
            ..success = true
            ..result = JSON.stringify(e)))));
    }
  }));
}

void _forwardChromeDebuggerEventToDwds(
    Debuggee source, String method, dynamic params) {
  final debugSession = _debugSessions
      .firstWhereOrNull((session) => session.appTabId == source.tabId);
  if (debugSession == null) return;
  final event = _extensionEventFor(method, params);
  if (method == 'Debugger.scriptParsed') {
    debugSession.sendBatchedEvent(event);
  } else {
    debugSession.sendEvent(event);
  }
}

void _openDevTools(String devToolsUrl, {required int dartAppTabId}) async {
  if (devToolsUrl.isEmpty) {
    debugError('DevTools URL is empty.');
    return;
  }
  final debugSession = _debugSessionForTab(dartAppTabId, type: TabType.dartApp);
  if (debugSession == null) {
    debugError('Debug session not found.');
    return;
  }
  // Send the DevTools URL to the extension panels:
  _sendDevToolsUrlMessage(devToolsUrl, dartAppTabId: dartAppTabId);
  // Open a separate tab / window if triggered through the extension icon:
  if (debugSession.trigger == Trigger.extensionIcon) {
    final devToolsOpener = await fetchStorageObject<DevToolsOpener>(
        type: StorageObject.devToolsOpener);
    final devToolsTab = await createTab(
      devToolsUrl,
      inNewWindow: devToolsOpener?.newWindow ?? false,
    );
    debugSession.devToolsTabId = devToolsTab.id;
  }
}

void _handleDebuggerDetach(Debuggee source, DetachReason reason) async {
  debugLog(
    'Debugger detached due to: $reason',
    verbose: true,
    prefix: '${source.tabId}',
  );
  final debugSession = _debugSessionForTab(source.tabId, type: TabType.dartApp);
  if (debugSession == null) return;
  debugLog('Removing debug session...');
  _removeDebugSession(debugSession);
  // Notify the extension panels that the debug session has ended:
  _sendStopDebuggingMessage(reason, dartAppTabId: source.tabId);
  // Maybe close the associated DevTools tab as well:
  final devToolsTabId = debugSession.devToolsTabId;
  if (devToolsTabId == null) return;
  final devToolsTab = await getTab(devToolsTabId);
  if (devToolsTab != null) {
    debugLog('Closing DevTools tab...');
    chrome.tabs.remove(devToolsTabId);
  }
}

void _removeDebugSession(_DebugSession debugSession) {
  // Note: package:sse will try to keep the connection alive, even after the
  // client has been closed. Therefore the extension sends an event to notify
  // DWDS that we should close the connection, instead of relying on the done
  // event sent when the client is closed. See details:
  // https://github.com/dart-lang/webdev/pull/1595#issuecomment-1116773378
  final event =
      _extensionEventFor('DebugExtension.detached', js_util.jsify({}));
  debugSession.sendEvent(event);
  debugSession.close();
  final removed = _debugSessions.remove(debugSession);
  if (!removed) {
    debugWarn('Could not remove debug session.');
  }
}

void sendConnectFailureMessage(ConnectFailureReason reason,
    {required int dartAppTabId}) async {
  final json = jsonEncode(serializers.serialize(ConnectFailure((b) => b
    ..tabId = dartAppTabId
    ..reason = reason.name)));
  sendRuntimeMessage(
      type: MessageType.connectFailure,
      body: json,
      sender: Script.background,
      recipient: Script.debuggerPanel);
}

void _sendDevToolsUrlMessage(String devToolsUrl,
    {required int dartAppTabId}) async {
  final json = jsonEncode(serializers.serialize(DevToolsUrl((b) => b
    ..tabId = dartAppTabId
    ..url = devToolsUrl)));
  sendRuntimeMessage(
      type: MessageType.devToolsUrl,
      body: json,
      sender: Script.background,
      recipient: Script.debuggerPanel);
}

void _sendStopDebuggingMessage(DetachReason reason,
    {required int dartAppTabId}) async {
  final json = jsonEncode(serializers.serialize(DebugStateChange((b) => b
    ..tabId = dartAppTabId
    ..reason = reason.name
    ..newState = DebugStateChange.stopDebugging)));
  sendRuntimeMessage(
      type: MessageType.debugStateChange,
      body: json,
      sender: Script.background,
      recipient: Script.debuggerPanel);
}

_DebugSession? _debugSessionForTab(tabId, {required TabType type}) {
  switch (type) {
    case TabType.dartApp:
      return _debugSessions
          .firstWhereOrNull((session) => session.appTabId == tabId);
    case TabType.devTools:
      return _debugSessions
          .firstWhereOrNull((session) => session.devToolsTabId == tabId);
  }
}

/// Construct an [ExtensionEvent] from [method] and [params].
ExtensionEvent _extensionEventFor(String method, dynamic params) {
  return ExtensionEvent((b) => b
    ..params = jsonEncode(json.decode(JSON.stringify(params)))
    ..method = jsonEncode(method));
}

Future<String> _getTabUrl(int tabId) async {
  final tab = await getTab(tabId);
  return tab?.url ?? '';
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}

class _DebugSession {
  // The tab ID that contains the running Dart application.
  final int appTabId;

  // What triggered the debug session (debugger panel, extension icon, etc.)
  final Trigger? trigger;

  // The tab ID that contains the corresponding Dart DevTools.
  late final int? devToolsTabId;

  // Socket client for communication with dwds extension backend.
  late final SocketClient _socketClient;

  // How often to send batched events.
  static const int _batchDelayMilliseconds = 1000;

  // Collect events into batches to be send periodically to the server.
  final _batchController =
      BatchedStreamController<ExtensionEvent>(delay: _batchDelayMilliseconds);
  late final StreamSubscription<List<ExtensionEvent>> _batchSubscription;

  _DebugSession({
    required client,
    required this.appTabId,
    required this.trigger,
    required void Function(String data) onIncoming,
    required void Function() onDone,
    required void Function(dynamic error) onError,
    required bool cancelOnError,
  }) : _socketClient = client {
    // Collect extension events and send them periodically to the server.
    _batchSubscription = _batchController.stream.listen((events) {
      _socketClient.sink.add(jsonEncode(serializers.serialize(BatchedEvents(
          (b) => b.events = ListBuilder<ExtensionEvent>(events)))));
    });
    // Listen for incoming events:
    _socketClient.stream.listen(
      onIncoming,
      onDone: onDone,
      onError: onError,
      cancelOnError: cancelOnError,
    );
  }

  set socketClient(SocketClient client) {
    _socketClient = client;

    // Collect extension events and send them periodically to the server.
    _batchSubscription = _batchController.stream.listen((events) {
      _socketClient.sink.add(jsonEncode(serializers.serialize(BatchedEvents(
          (b) => b.events = ListBuilder<ExtensionEvent>(events)))));
    });
  }

  void sendEvent<T>(T event) {
    _socketClient.sink.add(jsonEncode(serializers.serialize(event)));
  }

  void sendBatchedEvent(ExtensionEvent event) {
    _batchController.sink.add(event);
  }

  void close() {
    _socketClient.close();
    _batchSubscription.cancel();
    _batchController.close();
  }
}
