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

  // https://developer.chrome.com/docs/extensions/reference/debugger/#event-onDetach
  external OnDetachHandler get onDetach;

  // https://developer.chrome.com/docs/extensions/reference/debugger/#event-onEvent
  external OnEventHandler get onEvent;
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

  // https://developer.chrome.com/docs/extensions/reference/runtime/#event-onMessageExternal
  external OnMessageHandler get onMessageExternal;
}

@JS()
@anonymous
class Scripting {
  // https://developer.chrome.com/docs/extensions/reference/scripting/#method-executeScript
  external executeScript(InjectDetails details, Function? callback);
}

@JS()
@anonymous
class OnMessageHandler {
  external void addListener(
      void Function(dynamic, MessageSender, Function) callback);
}

@JS()
@anonymous
class Tabs {
  // https://developer.chrome.com/docs/extensions/reference/tabs/#method-query
  external Object query(QueryInfo queryInfo);

  // https://developer.chrome.com/docs/extensions/reference/tabs/#event-onActivated
  external OnActivatedHandler get onActivated;

  // https://developer.chrome.com/docs/extensions/reference/tabs/#event-onCreated
  external OnCreatedHandler get onCreated;

  // https://developer.chrome.com/docs/extensions/reference/tabs/#event-onRemoved
  external OnRemovedHandler get onRemoved;
}

@JS()
@anonymous
class OnActivatedHandler {
  external void addListener(void Function(ActiveInfo activeInfo) callback);
}

@JS()
@anonymous
class OnCreatedHandler {
  external void addListener(void Function(Tab tab) callback);
}

@JS()
@anonymous
class OnRemovedHandler {
  external void addListener(
      void Function(int tabId, RemoveInfo removeInfo) callback);
}

@JS()
@anonymous
class WebNavigation {
  // https://developer.chrome.com/docs/extensions/reference/webNavigation/#event-onCommitted
  external OnCommittedHandler get onCommitted;
}

@JS()
@anonymous
class OnCommittedHandler {
  external void addListener(void Function(NavigationInfo details) callback);
}

@JS()
@anonymous
class Windows {
  external OnFocusChangedHandler get onFocusChanged;
}

@JS()
@anonymous
class OnFocusChangedHandler {
  external void addListener(void Function(int windowId) callback);
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
