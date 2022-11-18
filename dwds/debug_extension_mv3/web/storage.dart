// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library storage;

import 'dart:async';
import 'dart:convert';
import 'dart:js_util';

import 'package:js/js.dart';

import 'chrome_api.dart';
import 'data_serializers.dart';
import 'web_api.dart';

/// Switch to true for debug logging.
bool enableDebugLogging = true;

enum StorageObject {
  debugInfo,
  devToolsOpener;

  String get keyName {
    switch (this) {
      case StorageObject.debugInfo:
        return 'debugInfo';
      case StorageObject.devToolsOpener:
        return 'devToolsOpener';
    }
  }
}

Future<bool> setStorageObject<T>({
  required StorageObject type,
  required T value,
  int? tabId,
  void Function()? callback,
}) {
  final storageKey = _createStorageKey(type, tabId);
  final json = jsonEncode(serializers.serialize(value));
  final storageObj = <String, String>{storageKey: json};
  final completer = Completer<bool>();
  chrome.storage.local.set(jsify(storageObj), allowInterop(() {
    if (callback != null) {
      callback();
    }
    _debugLog(storageKey, 'Set: $json');
    completer.complete(true);
  }));
  return completer.future;
}

Future<T?> fetchStorageObject<T>({required StorageObject type, int? tabId}) {
  final storageKey = _createStorageKey(type, tabId);
  final completer = Completer<T?>();
  chrome.storage.local.get([storageKey], allowInterop((Object storageObj) {
    final json = getProperty(storageObj, storageKey) as String?;
    if (json == null) {
      _debugWarn(storageKey, 'Does not exist.');
      completer.complete(null);
    } else {
      final value = serializers.deserialize(jsonDecode(json)) as T;
      _debugLog(storageKey, 'Fetched: $json');
      completer.complete(value);
    }
  }));
  return completer.future;
}

String _createStorageKey(StorageObject type, int? tabId) {
  if (tabId == null) return type.keyName;
  return '$tabId-${type.keyName}';
}

void _debugLog(String storageKey, String msg) {
  if (enableDebugLogging) {
    console.log('[$storageKey] $msg');
  }
}

void _debugWarn(String storageKey, String msg) {
  if (enableDebugLogging) {
    console.warn('[$storageKey] $msg');
  }
}
