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
      allowInterop(
        (Tab tab) {
          completer.complete(tab);
        },
      ),
    );
  }
  return completer.future;
}

Future<Tab?> getTab(int tabId) {
  final completer = Completer<Tab?>();
  chrome.tabs.get(tabId, allowInterop((tab) {
    completer.complete(tab);
  }));
  return completer.future;
}

Future<Tab?> get activeTab async {
  final completer = Completer<Tab?>();
  final query = QueryInfo(active: true, currentWindow: true);
  chrome.tabs.query(query, allowInterop((List tabs) {
    if (tabs.isNotEmpty) {
      completer.complete(tabs.first as Tab);
    } else {
      completer.complete(null);
    }
  }));
  return completer.future;
}

Future<bool> removeTab(int tabId) {
  final completer = Completer<bool>();
  chrome.tabs.remove(tabId, allowInterop(() {
    completer.complete(true);
  }));
  return completer.future;
}

Future<bool> injectScript(String scriptName, {required int tabId}) async {
  await promiseToFuture(chrome.scripting.executeScript(InjectDetails(
    target: Target(tabId: tabId),
    files: [scriptName],
  )));
  return true;
}

void onExtensionIconClicked(void Function(Tab) callback) {
  chrome.action.onClicked.addListener(callback);
}

void setExtensionIcon(IconInfo info) {
  chrome.action.setIcon(info, /*callback*/ null);
}

bool? _isDevMode;

bool isDevMode() {
  if (_isDevMode != null) {
    return _isDevMode!;
  }
  final extensionManifest = chrome.runtime.getManifest();
  final extensionName = getProperty(extensionManifest, 'name') ?? '';
  return extensionName.contains('DEV');
}

String addQueryParameters(
  String uri, {
  required Map<String, String> queryParameters,
}) {
  final originalUri = Uri.parse(uri);
  final newUri = originalUri.replace(queryParameters: {
    ...originalUri.queryParameters,
    ...queryParameters,
  });
  return newUri.toString();
}
