// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';

@JS()
external Chrome get chrome;

@JS()
@anonymous
class Chrome {
  external Action get action;
  external Debugger get debugger;
  external Runtime get runtime;
  external Scripting get scripting;
  external Tabs get tabs;
}

@JS()
@anonymous
class Action {
  // https://developer.chrome.com/docs/extensions/reference/action/#event-onClicked
  external OnClickedHandler get onClicked;
}

@JS()
@anonymous
class OnClickedHandler {
  external void addListener(void Function(Tab tab) callback);
}

@JS()
@anonymous
class Debugger {
  // https://developer.chrome.com/docs/extensions/reference/debugger/#method-attach
  external void attach(
      Debuggee target, String requiredVersion, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/debugger/#method-sendCommand
  external void sendCommand(Debuggee target, String method,
      Object? commandParams, Function? callback);
}

@JS()
@anonymous
class Runtime {
  // https://developer.chrome.com/docs/extensions/reference/runtime/#method-sendMessage
  external void sendMessage(
      String? id, Object? message, Object? options, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/runtime/#method-getURL
  external String getURL(String path);

  // https://developer.chrome.com/docs/extensions/reference/runtime/#event-onMessage
  external OnMessageHandler get onMessage;
}

@JS()
@anonymous
class OnMessageHandler {
  external void addListener(
      void Function(dynamic, MessageSender, Function) callback);
}

@JS()
@anonymous
class Scripting {
  // https://developer.chrome.com/docs/extensions/reference/scripting/#method-executeScript
  external executeScript(InjectDetails details, Function? callback);
}

@JS()
@anonymous
class Tabs {
  // https://developer.chrome.com/docs/extensions/reference/tabs/#method-query
  external Object query(QueryInfo queryInfo);

  // https://developer.chrome.com/docs/extensions/reference/tabs/#method-create
  external Object create(TabInfo tabInfo);
}

@JS()
@anonymous
class Debuggee {
  external int get tabId;
  external String get extensionId;
  external String get targetId;
  external factory Debuggee({int tabId, String? extensionId, String? targetId});
}

@JS()
@anonymous
class MessageSender {
  external String? get id;
  external Tab? get tab;
  external String? get url;
  external factory MessageSender({String? id, String? url, Tab? tab});
}

@JS()
@anonymous
class TabInfo {
  external bool? get active;
  external bool? get pinned;
  external String? get url;
  external factory TabInfo({bool? active, bool? pinned, String? url});
}

@JS()
@anonymous
class QueryInfo {
  external bool get active;
  external bool get currentWindow;
  external factory QueryInfo({bool? active, bool? currentWindow});
}

@JS()
@anonymous
class Tab {
  external int get id;
  external String get url;
}

@JS()
@anonymous
class InjectDetails {
  external Target get target;
  external List<String>? get files;
  external factory InjectDetails({Target target, List<String> files});
}

@JS()
@anonymous
class Target {
  external int get tabId;
  external factory Target({int tabId});
}
