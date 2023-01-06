// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:html';

import 'package:js/js.dart';

@JS()
external Chrome get chrome;

@JS()
@anonymous
class Chrome {
  external Action get action;
  external Debugger get debugger;
  external Devtools get devtools;
  external Notifications get notifications;
  external Runtime get runtime;
  external Scripting get scripting;
  external Storage get storage;
  external Tabs get tabs;
  external WebNavigation get webNavigation;
  external Windows get windows;
}

/// chrome.action APIs
/// https://developer.chrome.com/docs/extensions/reference/action

@JS()
@anonymous
class Action {
  external void setIcon(IconInfo iconInfo, Function? callback);

  external OnClickedHandler get onClicked;
}

@JS()
@anonymous
class OnClickedHandler {
  external void addListener(void Function(Tab tab) callback);
}

@JS()
@anonymous
class IconInfo {
  external String get path;
  external factory IconInfo({String path});
}

/// chrome.debugger APIs:
/// https://developer.chrome.com/docs/extensions/reference/debugger

@JS()
@anonymous
class Debugger {
  external void attach(
      Debuggee target, String requiredVersion, Function? callback);

  external Object detach(Debuggee target);

  external void sendCommand(Debuggee target, String method,
      Object? commandParams, Function? callback);

  external OnDetachHandler get onDetach;

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
class Debuggee {
  external int get tabId;
  external String get extensionId;
  external String get targetId;
  external factory Debuggee({int tabId, String? extensionId, String? targetId});
}

/// chrome.devtools APIs:

@JS()
@anonymous
class Devtools {
  // https://developer.chrome.com/docs/extensions/reference/devtools_inspectedWindow
  external InspectedWindow get inspectedWindow;

  // https://developer.chrome.com/docs/extensions/reference/devtools_panels/
  external Panels get panels;
}

@JS()
@anonymous
class InspectedWindow {
  external int get tabId;
}

@JS()
@anonymous
class Panels {
  external String get themeName;

  external void create(String title, String iconPath, String pagePath,
      void Function(ExtensionPanel)? callback);
}

@JS()
@anonymous
class ExtensionPanel {
  external OnHiddenHandler get onHidden;
  external OnShownHandler get onShown;
}

@JS()
@anonymous
class OnHiddenHandler {
  external void addListener(void Function() callback);
}

@JS()
@anonymous
class OnShownHandler {
  external void addListener(void Function(Window window) callback);
}

/// chrome.notification APIs:
/// https://developer.chrome.com/docs/extensions/reference/notifications

@JS()
@anonymous
class Notifications {
  external void create(
      String? notificationId, NotificationOptions options, Function? callback);
}

@JS()
@anonymous
class NotificationOptions {
  external factory NotificationOptions({
    String title,
    String message,
    String iconUrl,
    String type,
  });
}

/// chrome.runtime APIs:
/// https://developer.chrome.com/docs/extensions/reference/runtime

@JS()
@anonymous
class Runtime {
  external void connect(String? extensionId, ConnectInfo info);

  external void sendMessage(
      String? id, Object? message, Object? options, Function? callback);

  external Object getManifest();

  // Note: Not checking the lastError when one occurs throws a runtime exception.
  external ChromeError? get lastError;

  external ConnectionHandler get onConnect;

  external OnMessageHandler get onMessage;
}

@JS()
class ChromeError {
  external String get message;
}

@JS()
@anonymous
class ConnectInfo {
  external String? get name;
  external factory ConnectInfo({String? name});
}

@JS()
@anonymous
class Port {
  external String? get name;
  external void disconnect();
  external ConnectionHandler get onDisconnect;
}

@JS()
@anonymous
class ConnectionHandler {
  external void addListener(void Function(Port) callback);
}

@JS()
@anonymous
class OnMessageHandler {
  external void addListener(
      void Function(dynamic, MessageSender, Function) callback);
}

@JS()
@anonymous
class MessageSender {
  external String? get id;
  external Tab? get tab;
  external String? get url;
  external factory MessageSender({String? id, String? url, Tab? tab});
}

/// chrome.scripting APIs
/// https://developer.chrome.com/docs/extensions/reference/scripting

@JS()
@anonymous
class Scripting {
  external executeScript(InjectDetails details, Function? callback);
}

@JS()
@anonymous
class InjectDetails<T, U> {
  external Target get target;
  external T? get func;
  external List<U?>? get args;
  external List<String>? get files;
  external factory InjectDetails({
    Target target,
    T? func,
    List<U>? args,
    List<String>? files,
  });
}

@JS()
@anonymous
class Target {
  external int get tabId;
  external factory Target({int tabId});
}

/// chrome.storage APIs
/// https://developer.chrome.com/docs/extensions/reference/storage

@JS()
@anonymous
class Storage {
  external StorageArea get local;

  external StorageArea get session;

  external OnChangedHandler get onChanged;
}

@JS()
@anonymous
class StorageArea {
  external Object get(List<String> keys, void Function(Object result) callback);

  external Object set(Object items, void Function()? callback);

  external Object remove(List<String> keys, void Function()? callback);
}

@JS()
@anonymous
class OnChangedHandler {
  external void addListener(
    void Function(Object changes, String areaName) callback,
  );
}

/// chrome.tabs APIs
/// https://developer.chrome.com/docs/extensions/reference/tabs

@JS()
@anonymous
class Tabs {
  external Object query(QueryInfo queryInfo);

  external Object create(TabInfo tabInfo);

  external Object get(int tabId);

  external Object remove(int tabId);

  external OnActivatedHandler get onActivated;

  external OnRemovedHandler get onRemoved;
}

@JS()
@anonymous
class OnActivatedHandler {
  external void addListener(void Function(ActiveInfo activeInfo) callback);
}

@JS()
@anonymous
class OnRemovedHandler {
  external void addListener(void Function(int tabId, dynamic info) callback);
}

@JS()
@anonymous
class ActiveInfo {
  external int get tabId;
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

/// chrome.webNavigation APIs
/// https://developer.chrome.com/docs/extensions/reference/webNavigation

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
class NavigationInfo {
  external String get transitionType;
  external int get tabId;
  external String get url;
}

/// chrome.windows APIs
/// https://developer.chrome.com/docs/extensions/reference/windows

@JS()
@anonymous
class Windows {
  external Object create(WindowInfo? createData);

  external OnFocusChangedHandler get onFocusChanged;
}

@JS()
@anonymous
class OnFocusChangedHandler {
  external void addListener(void Function(int windowId) callback);
}

@JS()
@anonymous
class WindowInfo {
  external bool? get focused;
  external String? get url;
  external factory WindowInfo({bool? focused, String? url});
}

@JS()
@anonymous
class WindowObj {
  external int get id;
  external List<Tab> get tabs;
}
