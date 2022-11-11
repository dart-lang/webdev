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
  external void sendMessage(
      String? id, Object? message, Object? options, Function? callback);

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
class MessageSender {
  external String? get id;
  external Tab? get tab;
  external String? get url;
  external factory MessageSender({String? id, String? url, Tab? tab});
}

/// chrome.storage APIs
/// https://developer.chrome.com/docs/extensions/reference/storage

@JS()
@anonymous
class Storage {
  external StorageArea get local;
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
