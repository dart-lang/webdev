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
  external Storage get storage;
  external Tabs get tabs;
  external WebNavigation get webNavigation;
  external Windows get windows;
}

@JS()
@anonymous
class Action {
  // https://developer.chrome.com/docs/extensions/reference/action/#method-setIcon
  external void setIcon(IconInfo iconInfo, Function? callback);

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

  // https://developer.chrome.com/docs/extensions/reference/debugger/#method-detach
  external void detach(Debuggee target, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/debugger/#method-sendCommand
  external void sendCommand(Debuggee target, String method,
      Object? commandParams, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/debugger/#event-onEvent
  external OnEventHandler get onEvent;

    // https://developer.chrome.com/docs/extensions/reference/debugger/#event-onDetach
  external OnDetachHandler get onDetach;
}

@JS()
@anonymous
class OnDetachHandler {
  external void addListener(
      void Function(Debuggee source, String reason) callback);
}

@JS()
@anonymous
class OnEventHandler {
  external void addListener(
      void Function(Debuggee source, String method, Object? params) callback);
}

@JS()
@anonymous
class Runtime {
  // https://developer.chrome.com/docs/extensions/reference/runtime/#method-sendMessage
  external void sendMessage(
      String? id, Object? message, Object? options, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/runtime/#method-getURL
  external String getURL(String path);

  // https://developer.chrome.com/docs/extensions/reference/runtime/#property-lastError
  // Note: Not checking the lastError when one occurs throws a runtime exception.
  external ChromeError? get lastError;

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
class Storage {
  // https://developer.chrome.com/docs/extensions/reference/storage/#type-StorageArea
  external StorageArea get local;

  // https://developer.chrome.com/docs/extensions/reference/storage/#event-onChanged
  external OnChangedHandler get onChanged;
}

@JS()
@anonymous
class StorageArea {
  external Object get(List<String> keys, void Function(Object result) callback);

  external Object set(Object items, void Function()? callback);

  external void remove(List<String> keys, void Function()? callback);

  external Object clear(void Function()? callback);
}

@JS()
@anonymous
class OnChangedHandler {
  external void addListener(void Function(Object, String) callback);
}

@JS()
@anonymous
class Tabs {
  // https://developer.chrome.com/docs/extensions/reference/tabs/#method-query
  external Object query(QueryInfo queryInfo);

  // https://developer.chrome.com/docs/extensions/reference/tabs/#method-create
  external Object create(TabInfo tabInfo);

// https://developer.chrome.com/docs/extensions/reference/tabs/#method-get
  external Object get(int tabId);

  external void remove(List<int> tabIds, void Function()? callback);

    // https://developer.chrome.com/docs/extensions/reference/tabs/#event-onRemoved
  external OnRemovedHandler get onRemoved;
}

@JS()
@anonymous
class OnRemovedHandler {
  external void addListener(
      void Function(int tabId, RemoveInfo removeInfo) callback);
}

@JS()
@anonymous
class RemoveInfo {
  external int get windowId;
  external bool get isWindowClosing;
}

@JS()
@anonymous
class WebNavigation {
  // https://developer.chrome.com/docs/extensions/reference/webNavigation/#event-onCommitted
  external OnCommittedHandler get onCommitted;

  external OnCommittedHandler get onBeforeNavigate;
}


@JS()
@anonymous
class OnCommittedHandler {
  external void addListener(void Function(NavigationInfo details) callback);
}

@JS()
@anonymous
class NavigationInfo {
  external String get transitionType;
  external int get tabId;
}

@JS()
@anonymous
class Windows {
  external Object create(WindowInfo? createData);
}

@JS()
@anonymous
class WindowInfo {
  external bool? get focused;
  external String? get url;
  external String? get state;
  external factory WindowInfo({bool? focused, String? state, String? url});
}

@JS()
@anonymous
class WindowObj {
  external int get id;
  external List<Tab> get tabs;
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
  external String get url;
  external factory QueryInfo({bool? active, bool? currentWindow, String? url});
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

@JS()
class ChromeError {
  external String get message;
}

@JS()
@anonymous
class IconInfo {
  external String get path;
  external factory IconInfo({String path});
}