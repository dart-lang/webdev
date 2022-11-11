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
  external Runtime get runtime;
  external Scripting get scripting;
  external Storage get storage;
  external Tabs get tabs;
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

/// chrome.runtime APIs:
/// https://developer.chrome.com/docs/extensions/reference/runtime

@JS()
@anonymous
class Runtime {
  external void connect(String? extensionId, ConnectInfo info);

  external void sendMessage(
      String? id, Object? message, Object? options, Function? callback);

  external ConnectionHandler get onConnect;

  external OnMessageHandler get onMessage;
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
}

@JS()
@anonymous
class StorageArea {
  external Object get(List<String> keys, void Function(Object result) callback);

  external Object set(Object items, void Function()? callback);
}

/// chrome.tabs APIs
/// https://developer.chrome.com/docs/extensions/reference/tabs

@JS()
@anonymous
class Tabs {
  external Object query(QueryInfo queryInfo);

  external Object create(TabInfo tabInfo);

  external OnRemovedHandler get onRemoved;
}

@JS()
@anonymous
class OnRemovedHandler {
  external void addListener(void Function(int tabId, dynamic info) callback);
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

/// chrome.windows APIs
/// https://developer.chrome.com/docs/extensions/reference/windows

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
  external factory WindowInfo({bool? focused, String? url});
}

@JS()
@anonymous
class WindowObj {
  external int get id;
  external List<Tab> get tabs;
}
