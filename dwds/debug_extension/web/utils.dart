// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library utils;

import 'dart:async';
import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';

Future<Tab> createTab(String url, {bool inNewWindow = false}) {
  final completer = Completer<Tab>();
  if (inNewWindow) {
    chrome.windows.create(
      WindowInfo(focused: true, url: url),
      allowInterop(
        (WindowObj windowObj) {
          completer.complete(windowObj.tabs.first);
        },
      ),
    );
  } else {
    chrome.tabs.create(
      TabInfo(
        active: true,
        url: url,
      ),
      allowInterop(completer.complete),
    );
  }
  return completer.future;
}

Future<Tab?> getTab(int tabId) {
  final completer = Completer<Tab?>();
  chrome.tabs.get(tabId, allowInterop(completer.complete));
  return completer.future;
}

Future<Tab?> get activeTab {
  final completer = Completer<Tab?>();
  final query = QueryInfo(active: true, currentWindow: true);
  chrome.tabs.query(
    query,
    allowInterop((List tabs) {
      if (tabs.isNotEmpty) {
        completer.complete(tabs.first as Tab);
      } else {
        completer.complete(null);
      }
    }),
  );
  return completer.future;
}

Future<bool> removeTab(int tabId) {
  final completer = Completer<bool>();
  chrome.tabs.remove(
    tabId,
    allowInterop(() {
      completer.complete(true);
    }),
  );
  return completer.future;
}

void displayNotification(
  String message, {
  bool isError = false,
  Function? callback,
}) {
  chrome.notifications.create(
    // notificationId
    null,
    NotificationOptions(
      title: '${isError ? '[Error] ' : ''}Dart Debug Extension',
      message: message,
      iconUrl:
          isError ? 'static_assets/dart_warning.png' : 'static_assets/dart.png',
      type: 'basic',
    ),
    callback,
  );
}

void setExtensionIcon(IconInfo info) {
  if (isMV3) {
    _setExtensionIconMV3(
      info,
      // callback
      null,
    );
  } else {
    _setExtensionIconMV2(
      info,
      // callback
      null,
    );
  }
}

void setExtensionPopup(PopupDetails details) {
  if (isMV3) {
    _setExtensionPopupMV3(
      details,
      // callback
      null,
    );
  } else {
    _setExtensionPopupMV2(
      details,
      // callback
      null,
    );
  }
}

bool? _isDevMode;

bool get isDevMode {
  if (_isDevMode != null) {
    return _isDevMode!;
  }
  final extensionManifest = chrome.runtime.getManifest();
  final extensionName = getProperty(extensionManifest, 'name') ?? '';
  final isDevMode = extensionName.contains('DEV');
  _isDevMode = isDevMode;
  return isDevMode;
}

bool? _isMV3;

bool get isMV3 {
  if (_isMV3 != null) {
    return _isMV3!;
  }
  final extensionManifest = chrome.runtime.getManifest();
  final manifestVersion =
      getProperty(extensionManifest, 'manifest_version') ?? 2;
  final isMV3 = manifestVersion == 3;
  _isMV3 = isMV3;
  return isMV3;
}

String addQueryParameters(
  String uri, {
  required Map<String, String> queryParameters,
}) {
  final originalUri = Uri.parse(uri);
  final newUri = originalUri.replace(
    path: '', // Replace the /debugger path so that the inspector url works.
    queryParameters: {
      ...originalUri.queryParameters,
      ...queryParameters,
    },
  );
  return newUri.toString();
}

@JS('chrome.browserAction.setIcon')
external void _setExtensionIconMV2(IconInfo iconInfo, Function? callback);

@JS('chrome.action.setIcon')
external void _setExtensionIconMV3(IconInfo iconInfo, Function? callback);

@JS('chrome.browserAction.setPopup')
external void _setExtensionPopupMV2(PopupDetails details, Function? callback);

@JS('chrome.action.setPopup')
external void _setExtensionPopupMV3(PopupDetails details, Function? callback);

@JS()
@anonymous
class IconInfo {
  external String get path;
  external factory IconInfo({required String path});
}

@JS()
@anonymous
class PopupDetails {
  external int get tabId;
  external String get popup;
  external factory PopupDetails({required int tabId, required String popup});
}
