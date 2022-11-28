// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library tabs;

import 'dart:async';
import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';


Future<Tab> createTab(String url, {bool inNewWindow = false}) async {
  if (inNewWindow) {
    final windowPromise = chrome.windows.create(
      WindowInfo(focused: true, url: url),
    );
    final windowObj = await promiseToFuture<WindowObj>(windowPromise);
    return windowObj.tabs.first;
  }
  final tabPromise = chrome.tabs.create(TabInfo(
    active: true,
    url: url,
  ));
  return promiseToFuture<Tab>(tabPromise);
}