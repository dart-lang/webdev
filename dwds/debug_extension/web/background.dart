// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:async';
import 'dart:convert';
import 'dart:js';

import 'package:async/async.dart';
import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;
import 'package:pedantic/pedantic.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:sse/client/sse_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _notADartAppAlert = 'No Dart application detected.'
    ' Your development server should inject metadata to indicate support for'
    ' Dart debugging. This may require setting a flag. Check the documentation'
    ' for your development server.';

// GENERATE:
// pub run build_runner build web -o build -r
void main() {
  var startDebug = allowInterop((_) {
    var query = QueryInfo(active: true, currentWindow: true);
    Tab currentTab;

    // Sends commands to debugger attached to the current tab.
    //
    // Extracts the extension backend port from the injected JS.
    var callback = allowInterop((List<Tab> tabs) async {
      currentTab = tabs[0];
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
        var contextController = StreamController<int>();
        var contextQueue = StreamQueue(contextController.stream);
        addDebuggerListener(
            allowInterop((Debuggee source, String method, Object params) async {
          if (source.tabId != currentTab.id) {
            return;
          }
          if (method == 'Runtime.executionContextCreated') {
            var context = json.decode(stringify(params))['context'];
            contextController.add(context['id'] as int);
          }
        }));
        // We enqueue this work as we need to begin listening (`.hasNext`)
        // before events are received.
        unawaited(Future.microtask(() => sendCommand(
            Debuggee(tabId: currentTab.id),
            'Runtime.enable',
            EmptyParam(),
            allowInterop((e) {}))));
        var didAttach = false;
        // There is no way to calculate the number of existing execution contexts
        // so we wait for a short while to recieve a context.
        while (await contextQueue.hasNext.timeout(
            const Duration(milliseconds: 50),
            onTimeout: () => false)) {
          var context = await contextQueue.next;
          if (await _tryAttach(context, currentTab)) {
            didAttach = true;
            break;
          }
        }
        if (!didAttach) {
          alert(_notADartAppAlert);
          detach(Debuggee(tabId: currentTab.id), allowInterop(() {}));
          return;
        }
      }));
    });

    queryTabs(query, allowInterop((List tabs) {
      callback(List.from(tabs));
    }));
  });
  addListener(startDebug);

  // For testing only.
  onFakeClick = allowInterop(() {
    startDebug(null);
  });

  isDartDebugExtension = true;
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
  // Specifies whether the debugger is attached.
  //
  // A debugger is detached if it is closed by user or the target is closed.
  var attached = true;
  var client = uri.isScheme('ws') || uri.isScheme('wss')
      ? WebSocketClient(WebSocketChannel.connect(uri))
      : SseSocketClient(SseClient(uri.toString()));
  int devToolsTab;

  var queue = _EventQueue(client, currentTab, attached, dwdsVersion);
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
    }
  }, onDone: () {
    attached = false;
    queue._attached = false;
    client.close();
    return;
  }, onError: (_) {
    alert('Lost app connection.');
    detach(Debuggee(tabId: currentTab.id), allowInterop(() {}));
    attached = false;
    queue._attached = false;
    client.close();
  }, cancelOnError: true);

  await client.onOpen.first;
  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = appId
    ..instanceId = instanceId
    ..contextId = contextId
    ..tabUrl = currentTab.url))));

  sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.enable', EmptyParam(),
      allowInterop((e) {}));

  // Notifies the backend of debugger events.
  //
  // The listener of the `currentTab` receives events from all tabs.
  // We want to forward an event only if it originates from `currentTab`.
  // We know that if `source.tabId` and `currentTab.id` are the same.
  addDebuggerListener(allowInterop(queue._forwardOrEnqueue));

  onDetachAddListener(allowInterop((Debuggee source, DetachReason reason) {
    // Detach debugger from all tabs if debugger is cancelled by user.
    // Only one alert is displayed if there are multiple app tabs.
    if (reason.toString() == 'canceled_by_user' && attached) {
      if (source.tabId == currentTab.id) {
        alert('Debugger detached from all tabs. '
            'Click the extension to relaunch DevTools.');
      }
      attached = false;
      queue._attached = false;
      client.close();
      return;
    }

    // Detach debugger only from a tab that is closed.
    if (reason.toString() == 'target_closed' &&
        source.tabId == currentTab.id &&
        attached) {
      attached = false;
      queue._attached = false;
      client.close();
      return;
    }
  }));

  // Remembers the ID of the DevTools tab.
  tabsOnCreatedAddListener(allowInterop((Tab tab) async {
    devToolsTab ??= tab.id;
  }));

  // Stops debug service when DevTools tab closed.
  tabsOnRemovedAddListener(allowInterop((int tabId, _) {
    if (tabId == devToolsTab && attached) {
      detach(Debuggee(tabId: currentTab.id), allowInterop(() {}));
      attached = false;
      client.close();
      return;
    }
  }));
}

/// Maintains a queue of events to be batched, and forwards them periodically.
///
/// ScriptParsed events are queued, and all others are passed through directly.
class _EventQueue {
  _EventQueue(
      this._client, this._currentTab, this._attached, String dwdsVersion) {
    _supportsSkipLists =
        Version.parse(dwdsVersion ?? '0.0.0') >= Version.parse('7.1.0');
  }

  final SocketClient _client;
  final Tab _currentTab;
  bool _attached;
  bool _supportsSkipLists;

  /// The pending events.
  final queuedEvents = <ExtensionEvent>[];

  /// Forward [event] to the client immediately.
  void _forward(ExtensionEvent event) {
    _client.sink.add(jsonEncode(serializers.serialize(event)));
  }

  /// Construct an [ExtensionEvent] from [method] and [params].
  ExtensionEvent _extensionEventFor(String method, Object params) =>
      ExtensionEvent((b) => b
        ..params = jsonEncode(json.decode(stringify(params)))
        ..method = jsonEncode(method));

  /// Forward the event, or queue it up if it should be batched.
  void _forwardOrEnqueue(Debuggee source, String method, Object params) {
    if (source.tabId != _currentTab.id || !_attached) {
      return;
    }

    if (_supportsSkipLists && method == 'Debugger.scriptParsed') return;

    var event = _extensionEventFor(method, params);
    _forward(event);
  }
}

@JS('chrome.browserAction.onClicked.addListener')
external void addListener(Function callback);

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

@JS('chrome.tabs.onRemoved.addListener')
external void tabsOnRemovedAddListener(Function callback);

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
class Debuggee {
  external dynamic get tabId;
  external String get extensionId;
  external String get targetId;
  external factory Debuggee(
      {dynamic tabId, String extensionId, String targetId});
}

@JS()
@anonymous
class Tab {
  external int get id;
  external String get url;
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

abstract class SocketClient {
  StreamSink<dynamic> get sink;
  Stream<String> get stream;
  Stream<void> get onOpen;
  void close();
}

class SseSocketClient extends SocketClient {
  final SseClient _client;
  SseSocketClient(this._client);

  @override
  StreamSink<dynamic> get sink => _client.sink;

  @override
  Stream<String> get stream => _client.stream;

  @override
  Stream<void> get onOpen => _client.onOpen;

  @override
  void close() => _client.close();
}

class WebSocketClient extends SocketClient {
  final WebSocketChannel _channel;
  final StreamController<void> _openStreamController = StreamController<void>();
  WebSocketClient(this._channel) {
    _openStreamController.add(null);
  }

  @override
  StreamSink<dynamic> get sink => _channel.sink;
  @override
  Stream<String> get stream =>
      _channel.stream.map((dynamic o) => o?.toString());

  @override
  Stream<void> get onOpen => _openStreamController.stream;

  @override
  void close() => _channel.sink.close();
}
