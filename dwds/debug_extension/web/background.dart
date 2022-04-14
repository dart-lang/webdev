// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@JS()
library background;

import 'dart:async';
import 'dart:convert';
import 'dart:html';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:dwds/src/sockets.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;
import 'package:pub_semver/pub_semver.dart';
import 'package:sse/client/sse_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _notADartAppAlert = 'No Dart application detected.'
    ' Your development server should inject metadata to indicate support for'
    ' Dart debugging. This may require setting a flag. Check the documentation'
    ' for your development server.';

// Extensions allowed for cross-extension communication.
const _allowedExtensions = {
  'nbkbficgbembimioedhceniahniffgpl', // AngularDart DevTools
};

// Events forwarded to allowed extensions.
const _allowedEvents = {'Overlay.inspectNodeRequested'};

// Map of Chrome tab ID to encoded vm service protocol URI.
final _tabIdToEncodedUri = <int, String>{};

// Map of Chrome tab ID to warnings for that tab.
final _tabIdToWarning = <int, String>{};

final _debuggableTabs = <int>{};

final _tabsToAttach = <Tab>{};

final _debugSessions = <DebugSession>[];

final _devToolsPanelsNotifier = Notifier(<DevToolsPanel>[]);

// Keeps track of the most recent Dart tab that was opened. This is a heuristic
// to let us guess which tab the user is trying to debug if they start debugging
// from the Chrome DevTools Dart panel (which doesn't have a tab ID).
Tab _mostRecentDartTab;

// Keeps track of how debugging was triggered. This lets us know if we should
// open Dart DevTools in a new window/tab or embed it in Chrome DevTools.
DebuggerTrigger _debuggerTrigger;

class DebugSession {
  final SocketClient socketClient;

  // The tab ID that contains the running Dart application.
  final int appTabId;

  // The Dart app ID.
  final String appId;

  // The tab ID that contains the corresponding Dart DevTools.
  int devtoolsTabId;

  DebugSession(this.socketClient, this.appTabId, this.appId);
}

class DevToolsPanel {
  // The Dart app ID.
  final String appId;

  // The Chrome DevTools panel ID.
  String panelId;

  // The URI for the embedded Dart DevTools, or an empty string if the debugger
  // is disconnected.
  String devToolsUri = '';

  DevToolsPanel(this.appId);
}

enum DebuggerTrigger { extensionIcon, dartPanel, dwds }

void main() {
  // Start debugging when a user clicks the Dart Debug Extension:
  browserActionOnClickedAddListener(allowInterop((_) {
    _startDebugging(DebuggerTrigger.extensionIcon);
  }));

// Handles any incoming messages from the content scripts (detector, panel).
  onMessageAddListener(allowInterop(_handleMessageFromContentScripts));

  // Attaches a debug session to the app when the extension receives a
  // Runtime.executionContextCreated event from DWDS:
  addDebuggerListener(allowInterop(_maybeAttachDebugSession));

  // When a Dart application tab is closed, detach the corresponding debug
  // session:
  tabsOnRemovedAddListener(allowInterop(_maybeDetachDebugSessionForTab));

  // When a debug session is detached, remove the reference to it:
  onDetachAddListener(allowInterop((Debuggee source, DetachReason reason) {
    _maybeRemoveDebugSessionForTab(source.tabId);
  }));

  // Save the tab ID for the opened DevTools.
  tabsOnCreatedAddListener(allowInterop(_maybeSaveDevToolsTabId));

  // Forward debugger events to the backend if applicable.
  addDebuggerListener(allowInterop(_filterAndForwardToBackend));

  // Maybe update the extension icon when a user clicks the tab:
  tabsOnActivatedAddListener(allowInterop((ActiveInfo info) {
    _updateIcon();
  }));

  // Message handler enabling communication with external Chrome extensions:
  onMessageExternalAddListener(
      allowInterop(_handleMessageFromExternalExtensions));

  // Message forwarder enabling communication with external Chrome extensions:
  addDebuggerListener(allowInterop(_forwardMessageToExternalExtensions));

  // Maybe update the extension icon when the window focus changes:
  windowOnFocusChangeAddListener(allowInterop((_) {
    _updateIcon();
  }));

  // Maybe update the extension icon during tab navigation:
  webNavigationOnCommittedAddListener(
      allowInterop((NavigationInfo navigationInfo) {
    if (navigationInfo.transitionType != 'auto_subframe' &&
        _debuggableTabs.remove(navigationInfo.tabId)) {
      _updateIcon();
    }
  }));

  // Notify the panel script controlling the Dart DevTools panel in Chrome
  // DevTools of any relevant changes so that it can update accordingly:
  final devToolsPanelListener =
      Listener<List<DevToolsPanel>>(_notifyPanelScriptOfChanges);
  _devToolsPanelsNotifier.addListener(devToolsPanelListener);

  /// Everything after this is for testing only.
  /// TODO(elliette): Figure out if there is a workaround that would allow us to
  /// remove this.
  ///
  /// An automated click on the extension icon is not supported by WebDriver.
  /// We initiate a fake click from the `debug_extension_test`
  /// after the extension is loaded.
  onFakeClick = allowInterop(() {
    _startDebugging(DebuggerTrigger.extensionIcon);
  });

  /// This is how we determine the extension tab to connect to during E2E tests.
  isDartDebugExtension = true;
}

// Gets the current tab, then attaches the debugger to it:
void _startDebugging(DebuggerTrigger debuggerTrigger) {
  // Set how the debugging request was triggered. This will determine whether we
  // launch Dart DevTools in a new Chrome window / tab or in the Chrome DevTools
  // Dart panel:
  _debuggerTrigger = debuggerTrigger;

  final getCurrentTabQuery = QueryInfo(active: true, currentWindow: true);

  // Sends commands to debugger attached to the current tab.
  // Extracts the extension backend port from the injected JS.
  var attachDebuggerToTab = allowInterop(_attachDebuggerToTab);

  queryTabs(getCurrentTabQuery, allowInterop((List<Tab> tabs) {
    if (tabs != null && tabs.isNotEmpty) {
      attachDebuggerToTab(tabs[0]);
    } else if (_mostRecentDartTab != null) {
      attachDebuggerToTab(_mostRecentDartTab);
    } else {
      alert('''
          Could not find a Dart app to start debugging. 
          The Dart Debug Extension will turn blue when 
          a Dart application is detected.
          ''');
    }
  }));
}

void _attachDebuggerToTab(Tab currentTab) async {
  if (!_debuggableTabs.contains(currentTab.id)) return;

  if (_tabIdToWarning.containsKey(currentTab.id)) {
    alert(_tabIdToWarning[currentTab.id]);
    return;
  }

  attach(Debuggee(tabId: currentTab.id), '1.3', allowInterop(() async {
    if (lastError != null) {
      String alertMessage;
      if (lastError.message.contains('Cannot access') ||
          lastError.message.contains('Cannot attach')) {
        alertMessage = _notADartAppAlert;
      } else {
        alertMessage = 'DevTools is already opened on a different window.';
      }
      alert(alertMessage);
      return;
    }
    _tabsToAttach.add(currentTab);
    sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.enable', EmptyParam(),
        allowInterop((e) {}));
  }));
}

void _handleMessageFromContentScripts(
    Request request, Sender sender, Function sendResponse) {
  switch (request.sender) {
    case 'detector-script':
      _maybeMarkTabAsDebuggable(request, sender, sendResponse);
      break;
    case 'panel-script':
      _handleMessageFromPanelScript(request, sender);
      break;
  }
}

void _handleMessageFromPanelScript(Request request, Sender sender) {
  switch (request.message) {
    case 'devtools-open':
      _updateOrCreateDevToolsPanel(request.dartAppId, (panel) {
        panel.panelId = sender.id;
      });
      break;
    case 'start-debugging':
      _startDebugging(DebuggerTrigger.dartPanel);
      break;
  }
}

void _maybeMarkTabAsDebuggable(
    Request request, Sender sender, Function sendResponse) async {
  // Register any warnings for the tab:
  if (request.warning != '') {
    _tabIdToWarning[sender.tab.id] = request.warning;
  }
  _debuggableTabs.add(sender.tab.id);
  _updateIcon();
  // TODO(grouma) - We can conditionally auto start debugging here.
  // For example: _startDebugging(null);
  sendResponse(true);
}

void _maybeAttachDebugSession(
  Debuggee source,
  String method,
  Object params,
) async {
  // Return early if it's not a Runtime.executionContextCreated event (sent from
  // DWDS):
  if (method != 'Runtime.executionContextCreated') return;

  var context = json.decode(stringify(params))['context'];
  var tab = _tabsToAttach.firstWhere((tab) => tab.id == source.tabId,
      orElse: () => null);
  if (tab != null) {
    final launchInChromeDevTools =
        _debuggerTrigger == DebuggerTrigger.dartPanel;
    if (await _tryAttach(context['id'] as int, tab, launchInChromeDevTools)) {
      _tabsToAttach.remove(tab);
    }
  }
}

void _maybeDetachDebugSessionForTab(int tabId, _) {
  final removedTabId = _maybeRemoveDebugSessionForTab(tabId);

  if (removedTabId != -1) {
    detach(Debuggee(tabId: removedTabId), allowInterop(() {}));
  }
}

void _maybeSaveDevToolsTabId(Tab tab) async {
  // Remembers the ID of the DevTools tab.
  //
  // This assumes that the next launched tab after a session is created is the
  // DevTools tab.
  if (_debugSessions.isNotEmpty) _debugSessions.last.devtoolsTabId ??= tab.id;
}

void _handleMessageFromExternalExtensions(
    Request request, Sender sender, Function sendResponse) async {
  if (_allowedExtensions.contains(sender.id)) {
    if (request.name == 'chrome.debugger.sendCommand') {
      try {
        var options = request.options as SendCommandOptions;

        void sendResponseOrError([e]) {
          // No arguments indicate that an error occurred.
          if (e == null) {
            sendResponse(ErrorResponse()..error = stringify(lastError));
          } else {
            sendResponse(e);
          }
        }

        sendCommand(Debuggee(tabId: request.tabId), options.method,
            options.commandParams, allowInterop(sendResponseOrError));
      } catch (e) {
        sendResponse(ErrorResponse()..error = '$e');
      }
    } else if (request.name == 'dwds.encodedUri') {
      sendResponse(_tabIdToEncodedUri[request.tabId] ?? '');
    } else if (request.name == 'dwds.startDebugging') {
      _startDebugging(DebuggerTrigger.dwds);
      // TODO(grouma) - Actually determine if debugging initiated
      // successfully.
      sendResponse(true);
    } else {
      sendResponse(
          ErrorResponse()..error = 'Unknown request name: ${request.name}');
    }
  }
}

void _forwardMessageToExternalExtensions(
    Debuggee source, String method, Object params) async {
  if (_allowedEvents.contains(method)) {
    sendMessageToExtensions(Request(
        name: 'chrome.debugger.event',
        tabId: source.tabId,
        options: DebugEvent(method: method, params: params)));
  }
}

// Tries to remove the debug session for the specified tab. If no session is
// found, returns -1. Otherwise returns the tab ID.
int _maybeRemoveDebugSessionForTab(int tabId) {
  var session = _debugSessions.firstWhere(
      (session) => session.appTabId == tabId || session.devtoolsTabId == tabId,
      orElse: () => null);
  if (session != null) {
    consoleLog('SESSION IS NOT NULL, THEREFORE CLOSE SESSION');
    session.socketClient.close();
    _debugSessions.remove(session);

    // Notify the Dart DevTools panel that the session has been detached by
    // setting the URI to an empty string:
    _updateOrCreateDevToolsPanel(session.appId, (panel) {
      panel.devToolsUri = '';
    });

    return session.appTabId;
  } else {
    return -1;
  }
}

void _notifyPanelScriptOfChanges(List<DevToolsPanel> panels) {
  for (final panel in panels) {
    sendSimpleMessage(panel.panelId,
        SimpleMessage(recipient: 'panel-script', body: panel.devToolsUri));
  }
}

void sendMessageToExtensions(Request request) {
  for (var extensionId in _allowedExtensions) {
    try {
      sendMessage(extensionId, request, RequestOptions(), allowInterop(([e]) {
        if (e == null) {
          // Error sending message. Check lastError to silently fail.
          lastError;
        }
      }));
    } catch (_) {}
  }
}

/// Attempts to attach to the Dart application in the provided Tab and execution
/// context.
Future<bool> _tryAttach(
    int contextId, Tab tab, bool launchInChromeDevTools) async {
  var successCompleter = Completer<bool>();
  sendCommand(
      Debuggee(tabId: tab.id),
      'Runtime.evaluate',
      InjectedParams(
          expression:
              '[\$dartExtensionUri, \$dartAppId, \$dartAppInstanceId, window.\$dwdsVersion]',
          returnByValue: true,
          contextId: contextId), allowInterop((e) {
    String extensionUri, appId, instanceId, dwdsVersion;
    if (e.result.value == null) {
      successCompleter.complete(false);
      return;
    }
    extensionUri = e.result.value[0] as String;
    appId = e.result.value[1] as String;
    instanceId = e.result.value[2] as String;
    dwdsVersion = e.result.value[3] as String;
    _startSseClient(
      Uri.parse(extensionUri),
      appId,
      instanceId,
      contextId,
      tab,
      dwdsVersion,
      launchInChromeDevTools,
    );
    successCompleter.complete(true);
  }));
  return successCompleter.future;
}

// Starts an SSE client.
//
// Initiates a [DevToolsRequest], handles an [ExtensionRequest],
// and sends an [ExtensionEvent].
Future<void> _startSseClient(
  Uri uri,
  String appId,
  String instanceId,
  int contextId,
  Tab currentTab,
  String dwdsVersion,
  bool launchInChromeDevTools,
) async {
  if (Version.parse(dwdsVersion ?? '0.0.0') >= Version.parse('9.1.0')) {
    var authUri = uri.replace(path: authenticationPath);
    if (authUri.scheme == 'ws') authUri = authUri.replace(scheme: 'http');
    if (authUri.scheme == 'wss') authUri = authUri.replace(scheme: 'https');
    var authUrl = authUri.toString();
    try {
      var response = await HttpRequest.request(authUrl,
          method: 'GET', withCredentials: true);
      if (!response.responseText
          .contains('Dart Debug Authentication Success!')) {
        throw Exception('Not authenticated.');
      }
    } catch (_) {
      if (window.confirm(
          'Authentication required.\n\nClick OK to authenticate then try again.')) {
        // TODO(grouma) - see if we can get a callback on a successful auth
        // and automatically reinitiate the dev workflow.
        window.open(authUrl, 'Dart DevTools Authentication');
        detach(Debuggee(tabId: currentTab.id), allowInterop(() {}));
      }
      return;
    }
  }

  // Specifies whether the debugger is attached.
  //
  // A debugger is detached if it is closed by user or the target is closed.
  var client = uri.isScheme('ws') || uri.isScheme('wss')
      ? WebSocketClient(WebSocketChannel.connect(uri))
      : SseSocketClient(SseClient(uri.toString()));
  _debugSessions.add(DebugSession(client, currentTab.id, appId));
  print('Connected to DWDS version $dwdsVersion with appId=$appId');
  client.stream.listen((data) {
    var message = serializers.deserialize(jsonDecode(data));
    if (message is ExtensionRequest) {
      var params =
          BuiltMap<String, Object>(json.decode(message.commandParams)).toMap();
      sendCommand(Debuggee(tabId: currentTab.id), message.command,
          js_util.jsify(params), allowInterop(([e]) {
        // No arguments indicate that an error occurred.
        if (e == null) {
          client.sink
              .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
                ..id = message.id
                ..success = false
                ..result = stringify(lastError)))));
        } else {
          client.sink
              .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
                ..id = message.id
                ..success = true
                ..result = stringify(e)))));
        }
      }));
    } else if (message is ExtensionEvent) {
      if (message.method == 'dwds.encodedUri') {
        sendMessageToExtensions(Request(
            name: 'dwds.encodedUri',
            tabId: currentTab.id,
            options: message.params));
        _tabIdToEncodedUri[currentTab.id] = message.params;
      }

      if (message.method == 'dwds.devtoolsUri') {
        _updateOrCreateDevToolsPanel(appId, (panel) {
          panel.devToolsUri = message.params;
        });
      }
    }
  }, onDone: () {
    _tabIdToEncodedUri.remove(currentTab.id);
    _maybeDetachDebugSessionForTab(currentTab.id, null);
    return;
  }, onError: (_) {
    _tabIdToEncodedUri.remove(currentTab.id);
    alert('Lost app connection.');
    _maybeDetachDebugSessionForTab(currentTab.id, null);
  }, cancelOnError: true);

  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = appId
    ..instanceId = instanceId
    ..contextId = contextId
    ..tabUrl = currentTab.url
    ..uriOnly = launchInChromeDevTools))));

  sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.enable', EmptyParam(),
      allowInterop((e) {}));
}

void _updateOrCreateDevToolsPanel(
    String appId, void Function(DevToolsPanel panel) update) {
  final devToolsPanels = _devToolsPanelsNotifier.value;
  var panelAlreadyExists = false;
  for (final panel in devToolsPanels) {
    if (panel.appId == appId) {
      panelAlreadyExists = true;
      update(panel);
    }
  }
  if (!panelAlreadyExists) {
    final newPanel = DevToolsPanel(appId);
    update(newPanel);
    devToolsPanels.add(newPanel);
  }
  _devToolsPanelsNotifier.setValue(devToolsPanels);
}

void _updateIcon() {
  var query = QueryInfo(active: true, currentWindow: true);
  queryTabs(query, allowInterop((List tabs) {
    var tabList = List<Tab>.from(tabs);
    // If tabList is empty, the user has likely navigated to a different window.
    // Therefore, do not update the icon:
    if (tabList.isEmpty || tabList.first == null || tabList.first.id == null) {
      return;
    }

    if (_tabIdToWarning.containsKey(tabList.first.id)) {
      // Set the warning icon (red):
      setIcon(IconInfo(path: 'dart_warning.png'));
    } else if (_debuggableTabs.contains(tabList.first.id)) {
      // Set the debuggable icon (blue):
      _mostRecentDartTab = tabList.first;
      setIcon(IconInfo(path: 'dart.png'));
    } else {
      // Set the default icon (grey):
      setIcon(IconInfo(path: 'dart_grey.png'));
    }
  }));
}

/// Construct an [ExtensionEvent] from [method] and [params].
ExtensionEvent _extensionEventFor(String method, Object params) =>
    ExtensionEvent((b) => b
      ..params = jsonEncode(json.decode(stringify(params)))
      ..method = jsonEncode(method));

/// Forward debugger events to the backend if applicable.
void _filterAndForwardToBackend(Debuggee source, String method, Object params) {
  var debugSession = _debugSessions.firstWhere(
      (session) => session.appTabId == source.tabId,
      orElse: () => null);

  if (debugSession == null) return;

  var event = _extensionEventFor(method, params);

  debugSession.socketClient.sink.add(jsonEncode(serializers.serialize(event)));
}

class Notifier<T> {
  Notifier(T value) : _value = value;

  T _value;
  final List<Listener> _listeners = <Listener>[];

  T get value => _value;

  void setValue(T value) {
    _value = value;
    notifyListeners();
  }

  void addListener(Listener listener) {
    _listeners.add(listener);
  }

  void notifyListeners() {
    for (final listener in _listeners) {
      listener.onChange(_value);
    }
  }
}

class Listener<T> {
  Listener(this.onChange);

  void Function(T value) onChange;
}

@JS('chrome.browserAction.onClicked.addListener')
external void browserActionOnClickedAddListener(Function callback);

@JS('chrome.debugger.sendCommand')
external void sendCommand(
    Debuggee target, String method, Object commandParams, Function callback);

@JS('chrome.debugger.attach')
external void attach(
    Debuggee target, String requiredVersion, Function callback);

@JS('chrome.debugger.detach')
external void detach(Debuggee target, Function callback);

@JS('chrome.debugger.onEvent.addListener')
external dynamic addDebuggerListener(Function callback);

@JS('chrome.debugger.onDetach.addListener')
external dynamic onDetachAddListener(Function callback);

@JS('chrome.tabs.query')
external List<Tab> queryTabs(QueryInfo queryInfo, Function callback);

@JS('JSON.stringify')
external String stringify(o);

@JS('window.alert')
external void alert([String message]);

@JS('chrome.tabs.onCreated.addListener')
external void tabsOnCreatedAddListener(Function callback);

@JS('chrome.windows.onFocusChanged.addListener')
external void windowOnFocusChangeAddListener(Function callback);

@JS('chrome.webNavigation.onCommitted.addListener')
external void webNavigationOnCommittedAddListener(Function callback);

@JS('chrome.tabs.onActivated.addListener')
external void tabsOnActivatedAddListener(Function callback);

@JS('chrome.tabs.onRemoved.addListener')
external void tabsOnRemovedAddListener(Function callback);

@JS('chrome.runtime.onMessageExternal.addListener')
external void onMessageExternalAddListener(Function callback);

@JS('chrome.runtime.onMessage.addListener')
external void onMessageAddListener(Function callback);

@JS('chrome.browserAction.setIcon')
external void setIcon(IconInfo iconInfo);

@JS('chrome.runtime.sendMessage')
external void sendMessage(
    String id, Object message, Object options, Function callback);

@JS('chrome.runtime.sendMessage')
external void sendSimpleMessage(String id, SimpleMessage message);

// For debugging purposes:
@JS('console.log')
external void consoleLog(String header,
    [String style1, String style2, String style3]);

// Note: Not checking the lastError when one occurs throws a runtime exception.
@JS('chrome.runtime.lastError')
external ChromeError get lastError;

@JS()
class ChromeError {
  external String get message;
}

@JS()
@anonymous
class QueryInfo {
  external bool get active;
  external bool get currentWindow;
  external factory QueryInfo({bool active, bool currentWindow});
}

@JS()
@anonymous
class RemoveInfo {
  external int get windowId;
  external bool get isWindowClosing;
}

@JS()
@anonymous
class IconInfo {
  external String get path;
  external factory IconInfo({String path});
}

@JS()
@anonymous
class Debuggee {
  external int get tabId;
  external String get extensionId;
  external String get targetId;
  external factory Debuggee({int tabId, String extensionId, String targetId});
}

@JS()
@anonymous
class Tab {
  external int get id;
  external String get url;
}

@JS()
@anonymous
class ActiveInfo {
  external int get tabId;
}

@JS()
@anonymous
class NavigationInfo {
  external String get transitionType;
  external int get tabId;
}

@JS()
@anonymous
class SimpleMessage {
  external String get recipient;
  external String get body;
  external factory SimpleMessage({String recipient, String body});
}

@JS()
@anonymous
class Request {
  external String get dartAppId;
  external String get sender;
  external int get tabId;
  external String get name;
  external dynamic get options;
  external String get warning;
  external String get message;
  external factory Request({int tabId, String name, dynamic options});
}

@JS()
@anonymous
class DebugEvent {
  external factory DebugEvent({String method, dynamic params});
}

@JS()
@anonymous
class RequestOptions {}

@JS()
@anonymous
class SendCommandOptions {
  external String get method;
  external Object get commandParams;
}

@JS()
@anonymous
class Sender {
  external String get id;
  external Tab get tab;
}

@JS()
@anonymous
class ErrorResponse {
  external set error(String error);
}

@JS()
@anonymous
class RemoteObject {
  external EvaluationResult get result;
}

@JS()
@anonymous
class EvaluationResult {
  external dynamic get value;
}

@JS()
@anonymous
class EmptyParam {
  external factory EmptyParam();
}

@JS()
@anonymous
class InjectedParams {
  external String get expresion;
  external bool get returnByValue;
  external int get contextId;
  external factory InjectedParams(
      {String expression, bool returnByValue, int contextId});
}

@JS()
@anonymous
class ScriptIdParam {
  external String get scriptId;
  external factory ScriptIdParam({String scriptId});
}

@JS()
@anonymous
class DetachReason {}

/// For testing only.
//
/// An automated click on the extension icon is not supported by WebDriver.
/// We initiate a fake click from the `debug_extension_test`
/// after the extension is loaded.
@JS('fakeClick')
external set onFakeClick(void Function() f);

@JS('window.isDartDebugExtension')
external set isDartDebugExtension(_);
