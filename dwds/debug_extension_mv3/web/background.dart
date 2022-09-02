// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library background;

import 'dart:html';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'web_api.dart';

void main() {
  // Detect clicks on the Dart Debug Extension icon.
  chrome.action.onClicked.addListener(allowInterop((_) {
    _executeInjectorScript();
  }));
}

void _executeInjectorScript() async {
  final tabId = await _getTabId();
  if (tabId != null) {
    chrome.scripting.executeScript(
        InjectDetails(
            target: Target(tabId: tabId),
            files: ['iframe_injector.dart.js']), allowInterop((dynamic result) {
      console.log('RESULT IS $result');
    }));
  }
}

Future<int?> _getTabId() async {
  final query = QueryInfo(active: true, currentWindow: true);
  final tabs = List<Tab>.from(await promiseToFuture(chrome.tabs.query(query)));
  final tab = tabs.isNotEmpty ? tabs.first : null;
  return tab?.id;
}
