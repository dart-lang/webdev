// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:async';
import 'dart:convert';
import 'dart:js';

import 'package:built_collection/built_collection.dart';
import 'package:dwds/data/devtools_request.dart';
import 'package:dwds/data/extension_request.dart';
import 'package:dwds/data/serializers.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;
import 'package:pub_semver/pub_semver.dart';
import 'package:sse/client/sse_client.dart';

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
      attach(Debuggee(tabId: currentTab.id), '1.3', allowInterop(() {
        if (lastError != null) {
          alert('DevTools is already opened on a different window.');
          return;
        }
        sendCommand(
            Debuggee(tabId: currentTab.id),
            'Runtime.evaluate',
            InjectedParams(
                expression:
                    '[\$dartExtensionUri, \$dartAppId, \$dartAppInstanceId, window.\$dwdsVersion]',
                returnByValue: true), allowInterop((e) {
          String extensionUri, appId, instanceId, dwdsVersion;
          if (e.result.value == null) {
            alert('Unable to launch DevTools. This is not Dart application.');
            detach(Debuggee(tabId: currentTab.id), allowInterop(() {}));
            return;
          }
          extensionUri = e.result.value[0] as String;
          appId = e.result.value[1] as String;
          instanceId = e.result.value[2] as String;
          dwdsVersion = e.result.value[3] as String;
          startSseClient(
              extensionUri, appId, instanceId, currentTab, dwdsVersion);
        }));
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

// Starts an SSE client.
//
// Initiates a [DevToolsRequest], handles an [ExtensionRequest],
// and sends an [ExtensionEvent].
Future<void> startSseClient(String uri, String appId, String instanceId,
    Tab currentTab, String dwdsVersion) async {
  // Specifies whether the debugger is attached.
  //
  // A debugger is detached if it is closed by user or the target is closed.
  var attached = true;
  var client = SseClient(uri.toString());
  int devToolsTab;

  var queue = EventQueue(client, currentTab, attached, dwdsVersion);
  print('Connected to DWDS version $dwdsVersion with appId=$appId');
  client.stream.listen((data) {
    var message = serializers.deserialize(jsonDecode(data));
    if (message is ExtensionRequest) {
      var params =
          BuiltMap<String, Object>(json.decode(message.commandParams)).toMap();
      sendCommand(Debuggee(tabId: currentTab.id), message.command,
          js_util.jsify(params), allowInterop((e) {
        client.sink
            .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
              ..id = message.id
              ..success = true
              ..result = stringify(e)))));
      }));
    }
  }, onDone: () {
    attached = false;
    queue.attached = false;
    client.close();
    return;
  }, onError: (_) {
    alert('Lost app connection.');
    detach(Debuggee(tabId: currentTab.id), allowInterop(() {}));
    attached = false;
    queue.attached = false;
    client.close();
  }, cancelOnError: true);

  await client.onOpen.first;
  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = appId
    ..instanceId = instanceId
    ..tabUrl = currentTab.url))));

  sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.enable', EmptyParam(),
      allowInterop((e) {}));

  // Notifies the backend of debugger events.
  //
  // The listener of the `currentTab` receives events from all tabs.
  // We want to forward an event only if it originates from `currentTab`.
  // We know that if `source.tabId` and `currentTab.id` are the same.
  addDebuggerListener(allowInterop(queue.forwardOrEnqueue));

  onDetachAddListener(allowInterop((Debuggee source, DetachReason reason) {
    // Detach debugger from all tabs if debugger is cancelled by user.
    // Only one alert is displayed if there are multiple app tabs.
    if (reason.toString() == 'canceled_by_user' && attached) {
      if (source.tabId == currentTab.id) {
        alert('Debugger detached from all tabs. '
            'Click the extension to relaunch DevTools.');
      }
      attached = false;
      queue.attached = false;
      client.close();
      return;
    }

    // Detach debugger only from a tab that is closed.
    if (reason.toString() == 'target_closed' &&
        source.tabId == currentTab.id &&
        attached) {
      attached = false;
      queue.attached = false;
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
class EventQueue {
  EventQueue(this.client, this.currentTab, this.attached, String dwdsVersion) {
    supportsBatching = Version.parse(dwdsVersion) > Version.parse('0.8.1');
  }

  static const flushInterval = Duration(milliseconds: 250);

  final SseClient client;
  final Tab currentTab;
  bool attached;
  bool supportsBatching;

  /// The timer for how long we will wait before sending queued events.
  Timer timer;

  /// The pending events.
  final queuedEvents = <ExtensionEvent>[];

  void startTimer() {
    timer = Timer(flushInterval, flush);
  }

  /// Send all of our pending events in a batch.
  void flush() {
    var events = BuiltList<ExtensionEvent>.from(queuedEvents).toBuilder();
    client.sink.add(jsonEncode(
        serializers.serialize(BatchedEvents((b) => b..events = events))));
    queuedEvents.clear();
    timer = null;
  }

  /// Forward [event] to the client immediately.
  void forward(ExtensionEvent event) {
    client.sink.add(jsonEncode(serializers.serialize(event)));
  }

  /// Construct an [ExtensionEvent] from [method] and [params].
  ExtensionEvent extensionEventFor(String method, Object params) =>
      ExtensionEvent((b) => b
        ..params = jsonEncode(json.decode(stringify(params)))
        ..method = jsonEncode(method));

  /// Forward the event, or queue it up if it should be batched.
  void forwardOrEnqueue(Debuggee source, String method, Object params) {
    if (source.tabId != currentTab.id || !attached) {
      return;
    }
    var event = extensionEventFor(method, params);
    if (supportsBatching && method == 'Debugger.scriptParsed') {
      if (queuedEvents.isEmpty) {
        startTimer();
      }
      queuedEvents.add(event);
    } else {
      forward(event);
    }
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
  external factory InjectedParams({String expression, bool returnByValue});
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
