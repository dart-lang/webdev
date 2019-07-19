// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:convert';
import 'dart:js';

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
      sendCommand(Debuggee(tabId: currentTab.id), 'Debugger.enable',
          js_util.jsify({}), allowInterop((e) {}));
      sendCommand(Debuggee(tabId: currentTab.id), 'Runtime.evaluate',
          js_util.jsify({'expression': '\$extensionPort'}), allowInterop((e) {
        var port = e.result.value;
        startSseClient(port, currentTab);
      }));
    });

    queryTabs(query, allowInterop((List tabs) {
      callback(List.from(tabs));
    }));
  }));
}

// Starts an SSE client.
//
// Creates 2 channels which connect to the SSE handler at the extension
// backend, send a simple message.
Future<void> startSseClient(port, currentTab) async {
  var client = SseClient('http://localhost:$port/test');
  client.stream.listen((data) {
    var message = serializers.deserialize(jsonDecode(data));
    if (message is ExtensionRequest) {
      sendCommand(Debuggee(tabId: currentTab.id), message.command,
          js_util.jsify(message.commandParams.toMap()), allowInterop((e) {
        client.sink
            .add(jsonEncode(serializers.serialize(ExtensionResponse((b) => b
              ..id = message.id
              ..success = true
              ..result = stringify(e)))));
      }));
    }

    // Listens for console events and prints the script being logged.
    addDebuggerListener((Debuggee source, String method, Object params) {
      var decodedParam = json.decode(stringify(params));
      var id = decodedParam['scriptId'];
      sendCommand(Debuggee(tabId: currentTab.id), 'Debugger.getScriptSource',
          js_util.jsify({'scriptId': id}), allowInterop((script) {
        var decodedScript = json.decode(stringify(script));
        print(decodedScript['scriptSource']);
      }));
    });
  }, onError: (e) {
    client.close();
  }, cancelOnError: true);

  var client2 = SseClient('http://localhost:$port/test');
  await client2.onOpen.first;
  client2.sink.add('This is channel 2.');
}

@JS('chrome.browserAction.onClicked.addListener')
external void addListener(Function callback);

@JS('chrome.debugger.sendCommand')
external void sendCommand(
    Debuggee target, String method, Object commandParams, Function callback);

@JS('chrome.debugger.attach')
external void attach(
    Debuggee target, String requiredVersion, Function callback);

@JS('chrome.debugger.onEvent.addListener')
external dynamic addDebuggerListener(Function callback);

@JS('chrome.tabs.query')
external List<Tab> queryTabs(QueryInfo queryInfo, Function callback);

@JS('JSON.stringify')
external String stringify(o);

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
