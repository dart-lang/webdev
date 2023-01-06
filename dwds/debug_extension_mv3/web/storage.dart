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
import 'logger.dart';

enum StorageObject {
  debugInfo,
  devToolsOpener,
  encodedUri;

  Persistance get persistance {
    switch (this) {
      case StorageObject.debugInfo:
        return Persistance.sessionOnly;
      case StorageObject.devToolsOpener:
        return Persistance.acrossSessions;
      case StorageObject.encodedUri:
        return Persistance.sessionOnly;
    }
  }
}

enum Persistance {
  sessionOnly,
  acrossSessions;
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
  final storageArea = _getStorageArea(type.persistance);
  storageArea.set(jsify(storageObj), allowInterop(() {
    if (callback != null) {
      callback();
    }
    debugLog('Set: $json', prefix: storageKey);
    completer.complete(true);
  }));
  return completer.future;
}

Future<T?> fetchStorageObject<T>({required StorageObject type, int? tabId}) {
  final storageKey = _createStorageKey(type, tabId);
  final completer = Completer<T?>();
  final storageArea = _getStorageArea(type.persistance);
  storageArea.get([storageKey], allowInterop((Object storageObj) {
    final json = getProperty(storageObj, storageKey) as String?;
    if (json == null) {
      debugWarn('Does not exist.', prefix: storageKey);
      completer.complete(null);
    } else {
      final value = serializers.deserialize(jsonDecode(json)) as T;
      debugLog('Fetched: $json', prefix: storageKey);
      completer.complete(value);
    }
  }));
  return completer.future;
}

Future<bool> removeStorageObject<T>({required StorageObject type, int? tabId}) {
  final storageKey = _createStorageKey(type, tabId);
  final completer = Completer<bool>();
  final storageArea = _getStorageArea(type.persistance);
  storageArea.remove([storageKey], allowInterop(() {
    debugLog('Removed object.', prefix: storageKey);
    completer.complete(true);
  }));
  return completer.future;
}

StorageArea _getStorageArea(Persistance persistance) {
  switch (persistance) {
    case Persistance.acrossSessions:
      return chrome.storage.local;
    case Persistance.sessionOnly:
      return chrome.storage.session;
  }
}

String _createStorageKey(StorageObject type, int? tabId) {
  if (tabId == null) return type.name;
  return '$tabId-${type.name}';
}
