// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@JS()
library background;

import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:js';

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

final _debuggableTabs = <int>{};

final _tabsToAttach = <Tab>{};

final _debugSessions = <DebugSession>[];

class DebugSession {
  final SocketClient socketClient;

  // The tab ID that contains the running Dart application.
  final int appTabId;

  // The tab ID that contains the corresponding Dart DevTools.
  int devtoolsTabId;

  DebugSession(this.socketClient, this.appTabId);
}

void main() {
  var startDebugging = allowInterop((_) {
    var query = QueryInfo(active: true, currentWindow: true);
    Tab currentTab;

    // Sends commands to debugger attached to the current tab.
    //
    // Extracts the extension backend port from the injected JS.
    var callback = allowInterop((List<Tab> tabs) async {
      currentTab = tabs[0];
      if (!_debuggableTabs.contains(currentTab.id)) return;
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
        sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.enable',
            EmptyParam(), allowInterop((e) {}));
      }));
    });

    queryTabs(query, allowInterop((List tabs) {
      callback(List.from(tabs));
    }));
  });
  browserActionOnClickedAddListener(startDebugging);

  // For testing only.
  onFakeClick = allowInterop(() {
    startDebugging(null);
  });

  isDartDebugExtension = true;

  onMessageAddListener(allowInterop(
      (Request request, Sender sender, Function sendResponse) async {
    _debuggableTabs.add(sender.tab.id);
    _updateIcon();
    // TODO(grouma) - We can conditionally auto start debugging here.
    // For example: startDebugging(null);
    sendResponse(true);
  }));

  tabsOnActivatedAddListener(allowInterop((ActiveInfo info) {
    _updateIcon();
  }));

  addDebuggerListener(allowInterop((
    Debuggee source,
    String method,
    Object params,
  ) async {
    if (method == 'Runtime.executionContextCreated') {
      var context = json.decode(stringify(params))['context'];
      var tab = _tabsToAttach.firstWhere((tab) => tab.id == source.tabId,
          orElse: () => null);
      if (tab != null) {
        if (await _tryAttach(context['id'] as int, tab)) {
          _tabsToAttach.remove(tab);
        }
      }
    }
  }));

  webNavigationOnCommittedAddListener(
      allowInterop((NavigationInfo navigationInfo) {
    if (navigationInfo.transitionType != 'auto_subframe' &&
        _debuggableTabs.remove(navigationInfo.tabId)) {
      _updateIcon();
    }
  }));

  windowOnFocusChangeAddListener(allowInterop((_) {
    _updateIcon();
  }));

  tabsOnRemovedAddListener(allowInterop((int tabId, _) {
    _debuggableTabs.remove(tabId);
    var session = _debugSessions.firstWhere(
        (session) =>
            session.appTabId == tabId || session.devtoolsTabId == tabId,
        orElse: () => null);
    if (session != null) {
      session.socketClient.close();
      _debugSessions.remove(session);
      detach(Debuggee(tabId: session.appTabId), allowInterop(() {}));
    }
  }));

  onDetachAddListener(allowInterop((Debuggee source, DetachReason reason) {
    var session = _debugSessions.firstWhere(
        (session) => session.appTabId == source.tabId,
        orElse: () => null);
    if (session != null) {
      session.socketClient.close();
      _debugSessions.remove(session);
    }
  }));

  tabsOnCreatedAddListener(allowInterop((Tab tab) async {
    // Remembers the ID of the DevTools tab.
    //
    // This assumes that the next launched tab after a session is created is the
    // DevTools tab.
    if (_debugSessions.isNotEmpty) _debugSessions.last.devtoolsTabId ??= tab.id;
  }));

  addDebuggerListener(allowInterop(_filterAndForward));

  onMessageExternalAddListener(allowInterop(
      (Request request, Sender sender, Function sendResponse) async {
    if (_allowedExtensions.contains(sender.id)) {
      if (request.name == 'chrome.debugger.sendCommand') {
        try {
          var options = request.options as SendCommandOptions;
          sendCommand(Debuggee(tabId: request.tabId), options.method,
              options.commandParams, allowInterop(([e]) {
            // No arguments indicate that an error occurred.
            if (e == null) {
              sendResponse(ErrorResponse()..error = stringify(lastError));
            } else {
              sendResponse(e);
            }
          }));
        } catch (e) {
          sendResponse(ErrorResponse()..error = '$e');
        }
      } else if (request.name == 'dwds.encodedUri') {
        sendResponse(_tabIdToEncodedUri[request.tabId] ?? '');
      } else if (request.name == 'dwds.startDebugging') {
        startDebugging(null);
        // TODO(grouma) - Actually determine if debugging initiated
        // successfully.
        sendResponse(true);
      } else {
        sendResponse(
            ErrorResponse()..error = 'Unknown request name: ${request.name}');
      }
    }
  }));

  addDebuggerListener(
      allowInterop((Debuggee source, String method, Object params) async {
    if (_allowedEvents.contains(method)) {
      sendMessageToExtensions(Request(
          name: 'chrome.debugger.event',
          tabId: source.tabId,
          options: DebugEvent(method: method, params: params)));
    }
  }));
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
Future<bool> _tryAttach(int contextId, Tab tab) async {
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
  _debugSessions.add(DebugSession(client, currentTab.id));
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
    }
  }, onDone: () {
    _tabIdToEncodedUri.remove(currentTab.id);
    client.close();
    return;
  }, onError: (_) {
    _tabIdToEncodedUri.remove(currentTab.id);
    alert('Lost app connection.');
    client.close();
  }, cancelOnError: true);

  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = appId
    ..instanceId = instanceId
    ..contextId = contextId
    ..tabUrl = currentTab.url))));

  sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.enable', EmptyParam(),
      allowInterop((e) {}));
}

void _updateIcon() {
  var query = QueryInfo(active: true, currentWindow: true);
  queryTabs(query, allowInterop((List tabs) {
    var tabList = List<Tab>.from(tabs);
    if (tabList.isEmpty || _debuggableTabs.contains(tabList.first.id)) {
      setIcon(IconInfo(path: 'dart.png'));
    } else {
      setIcon(IconInfo(path: 'dart_grey.png'));
    }
  }));
}

/// Construct an [ExtensionEvent] from [method] and [params].
ExtensionEvent _extensionEventFor(String method, Object params) =>
    ExtensionEvent((b) => b
      ..params = jsonEncode(json.decode(stringify(params)))
      ..method = jsonEncode(method));

/// Forward the event if applicable.
void _filterAndForward(Debuggee source, String method, Object params) {
  var debugSession = _debugSessions.firstWhere(
      (session) => session.appTabId == source.tabId,
      orElse: () => null);

  if (debugSession == null) return;

  if (method == 'Debugger.scriptParsed') return;

  var event = _extensionEventFor(method, params);

  debugSession.socketClient.sink.add(jsonEncode(serializers.serialize(event)));
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
class Request {
  external int get tabId;
  external String get name;
  external dynamic get options;
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
