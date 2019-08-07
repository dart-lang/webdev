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
import 'package:sse/client/sse_client.dart';

// GENERATE:
// pub run build_runner build web -o build -r
void main() {
  addListener(allowInterop((e) {
    var query = QueryInfo(active: true, currentWindow: true);
    Tab currentTab;

    // Sends commands to debugger attached to the current tab.
    //
    // Extracts the extension backend port from the injected JS.
    var callback = allowInterop((List<Tab> tabs) async {
      currentTab = tabs[0];
      attach(Debuggee(tabId: currentTab.id), '1.3', allowInterop(() {}));
      sendCommand(
          Debuggee(tabId: currentTab.id),
          'Runtime.evaluate',
          InjectedParams(
              expression:
                  '[\$extensionPort, \$extensionHostname, \$dartAppId, \$dartAppInstanceId]',
              returnByValue: true), allowInterop((e) {
        String port, hostname, appId, instanceId;
        if (e.result.value == null) {
          alert('Unable to launch DevTools. This is not Dart application.');
          detach(Debuggee(tabId: currentTab.id), allowInterop(() {}));
          return;
        }
        port = e.result.value[0] as String;
        hostname = e.result.value[1] as String;
        appId = e.result.value[2] as String;
        instanceId = e.result.value[3] as String;

        startSseClient(hostname, port, appId, instanceId, currentTab);
      }));
    });

    queryTabs(query, allowInterop((List tabs) {
      callback(List.from(tabs));
    }));
  }));
}

// Starts an SSE client.
//
// Initiates a [DevToolsRequest], handles an [ExtensionRequest],
// and sends an [ExtensionEvent].
Future<void> startSseClient(
    hostname, port, appId, instanceId, currentTab) async {
  var client = SseClient('http://$hostname:$port/\$debug');
  await client.onOpen.first;
  client.sink.add(jsonEncode(serializers.serialize(DevToolsRequest((b) => b
    ..appId = appId as String
    ..instanceId = instanceId as String
    ..tabUrl = currentTab.url as String))));
  sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.enable', EmptyParam(),
      allowInterop((e) {}));

  // Notifies the backend of debugger events.
  //
  // The listener of the `currentTab` receives events from all tabs.
  // We want to forward an event only if it originates from `currentTab`.
  // We know that if `source.tabId` and `currentTab.id` are the same.
  addDebuggerListener(
      allowInterop((Debuggee source, String method, Object params) {
    if (source.tabId == currentTab.id) {
      client.sink.add(jsonEncode(serializers.serialize(ExtensionEvent((b) => b
        ..params = jsonEncode(json.decode(stringify(params)))
        ..method = jsonEncode(method)))));
    }
  }));

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
  }, onError: (e) {
    client.close();
  }, cancelOnError: true);
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

@JS('chrome.tabs.query')
external List<Tab> queryTabs(QueryInfo queryInfo, Function callback);

@JS('JSON.stringify')
external String stringify(o);

@JS('window.alert')
external void alert([String message]);

@JS()
@anonymous
class QueryInfo {
  external bool get active;
  external bool get currentWindow;
  external factory QueryInfo({bool active, bool currentWindow});
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
