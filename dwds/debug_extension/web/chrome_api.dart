// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:js/js.dart';

@JS()
external Chrome get chrome;

@JS()
@anonymous
class Chrome {
  external _BrowserAction get browserAction;
  external _Debugger get debugger;
  external _Runtime get runtime;
  external _Tabs get tabs;
  external _WebNavigation get webNavigation;
  external _Windows get windows;
}

@JS()
@anonymous
class ActiveInfo {
  external int get tabId;
}

@JS()
class ChromeError {
  external String get message;
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
class IconInfo {
  external String get path;
  external factory IconInfo({String path});
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
class NavigationInfo {
  external String get transitionType;
  external int get tabId;
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
class RemoveInfo {
  external int get windowId;
  external bool get isWindowClosing;
}

@JS()
@anonymous
class Tab {
  external int get id;
  external String get url;
}

@JS()
@anonymous
class UrlFilter {
  external String? get hostContains;
  external String? get hostEquals;
  external String? get hostPrefix;
  external String? get hostSuffix;
}

@JS()
@anonymous
class _BrowserAction {
  // https://developer.chrome.com/docs/extensions/reference/browserAction/#method-setIcon
  external void setIcon(IconInfo iconInfo, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/browserAction/#event-onClicked
  external _OnClickedHandler get onClicked;
}

@JS()
@anonymous
class _OnClickedHandler {
  external void addListener(void Function(Tab tab) callback);
}

@JS()
@anonymous
class _Debugger {
  // https://developer.chrome.com/docs/extensions/reference/debugger/#method-attach
  external void attach(
      Debuggee target, String requiredVersion, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/debugger/#method-detach
  external void detach(Debuggee target, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/debugger/#method-sendCommand
  external void sendCommand(Debuggee target, String method,
      Object? commandParams, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/debugger/#event-onDetach
  external _OnDetachHandler get onDetach;

  // https://developer.chrome.com/docs/extensions/reference/debugger/#event-onEvent
  external _OnEventHandler get onEvent;
}

@JS()
@anonymous
class _OnDetachHandler {
  external void addListener(
      void Function(Debuggee source, String reason) callback);
}

@JS()
@anonymous
class _OnEventHandler {
  external void addListener(
      void Function(Debuggee source, String method, dynamic params) callback);
}

@JS()
@anonymous
class _Runtime {
  // https://developer.chrome.com/docs/extensions/reference/runtime/#method-sendMessage
  external void sendMessage(
      String? id, Object? message, Object? options, Function? callback);

  // https://developer.chrome.com/docs/extensions/reference/runtime/#property-lastError
  // Note: Not checking the lastError when one occurs throws a runtime exception.
  external ChromeError? get lastError;

  // https://developer.chrome.com/docs/extensions/reference/runtime/#event-onMessage
  external _OnMessageHandler get onMessage;

  // https://developer.chrome.com/docs/extensions/reference/runtime/#event-onMessageExternal
  external _OnMessageHandler get onMessageExternal;
}

@JS()
@anonymous
class _OnMessageHandler {
  external void addListener(
      void Function(dynamic, MessageSender, Function) callback);
}

@JS()
@anonymous
class _Tabs {
  // https://developer.chrome.com/docs/extensions/reference/tabs/#method-query
  external List<Tab> query(
      QueryInfo queryInfo, void Function(List<Tab>) callback);

  // https://developer.chrome.com/docs/extensions/reference/tabs/#event-onActivated
  external _OnActivatedHandler get onActivated;

  // https://developer.chrome.com/docs/extensions/reference/tabs/#event-onCreated
  external _OnCreatedHandler get onCreated;

  // https://developer.chrome.com/docs/extensions/reference/tabs/#event-onRemoved
  external _OnRemovedHandler get onRemoved;
}

@JS()
@anonymous
class _OnActivatedHandler {
  external void addListener(void Function(ActiveInfo activeInfo) callback);
}

@JS()
@anonymous
class _OnCreatedHandler {
  external void addListener(void Function(Tab tab) callback);
}

@JS()
@anonymous
class _OnRemovedHandler {
  external void addListener(
      void Function(int tabId, RemoveInfo removeInfo) callback);
}

@JS()
@anonymous
class _WebNavigation {
  // https://developer.chrome.com/docs/extensions/reference/webNavigation/#event-onCommitted
  external _OnCommittedHandler get onCommitted;
}

@JS()
@anonymous
class _OnCommittedHandler {
  external void addListener(void Function(NavigationInfo details) callback);
}

@JS()
@anonymous
class _Windows {
  external _OnFocusChangedHandler get onFocusChanged;
}

@JS()
@anonymous
class _OnFocusChangedHandler {
  external void addListener(void Function(int windowId) callback);
}
