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
import 'utils.dart';

enum StorageObject {
  debugInfo,
  devToolsOpener,
  devToolsUri,
  encodedUri,
  isAuthenticated,
  multipleAppsDetected;

  Persistence get persistence {
    switch (this) {
      case StorageObject.debugInfo:
        return Persistence.sessionOnly;
      case StorageObject.devToolsOpener:
        return Persistence.acrossSessions;
      case StorageObject.devToolsUri:
        return Persistence.sessionOnly;
      case StorageObject.encodedUri:
        return Persistence.sessionOnly;
      case StorageObject.isAuthenticated:
        return Persistence.sessionOnly;
      case StorageObject.multipleAppsDetected:
        return Persistence.sessionOnly;
    }
  }
}

enum Persistence {
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
  final json =
      value is String ? value : jsonEncode(serializers.serialize(value));
  final storageObj = <String, String>{storageKey: json};
  final completer = Completer<bool>();
  final storageArea = _getStorageArea(type.persistence);
  storageArea.set(
    jsify(storageObj),
    allowInterop(() {
      if (callback != null) {
        callback();
      }
      debugLog('Set: $json', prefix: storageKey);
      completer.complete(true);
    }),
  );
  return completer.future;
}

Future<T?> fetchStorageObject<T>({required StorageObject type, int? tabId}) {
  final storageKey = _createStorageKey(type, tabId);
  final completer = Completer<T?>();
  final storageArea = _getStorageArea(type.persistence);
  storageArea.get(
    [storageKey],
    allowInterop((Object? storageObj) {
      if (storageObj == null) {
        debugWarn('Does not exist.', prefix: storageKey);
        completer.complete(null);
        return;
      }
      final json = getProperty(storageObj, storageKey) as String?;
      if (json == null) {
        debugWarn('Does not exist.', prefix: storageKey);
        completer.complete(null);
      } else {
        debugLog('Fetched: $json', prefix: storageKey);
        if (T == String) {
          completer.complete(json as T);
        } else {
          final value = serializers.deserialize(jsonDecode(json)) as T;
          completer.complete(value);
        }
      }
    }),
  );
  return completer.future;
}

Future<List<T>> fetchAllStorageObjectsOfType<T>({required StorageObject type}) {
  final completer = Completer<List<T>>();
  final storageArea = _getStorageArea(type.persistence);
  storageArea.get(
    null,
    allowInterop((Object? storageContents) {
      if (storageContents == null) {
        debugWarn('No storage objects of type exist.', prefix: type.name);
        completer.complete([]);
        return;
      }
      final allKeys = List<String>.from(objectKeys(storageContents));
      final storageKeys = allKeys.where((key) => key.contains(type.name));
      final result = <T>[];
      for (final key in storageKeys) {
        final json = getProperty(storageContents, key) as String?;
        if (json != null) {
          if (T == String) {
            result.add(json as T);
          } else {
            result.add(serializers.deserialize(jsonDecode(json)) as T);
          }
        }
      }
      completer.complete(result);
    }),
  );
  return completer.future;
}

Future<bool> removeStorageObject<T>({required StorageObject type, int? tabId}) {
  final storageKey = _createStorageKey(type, tabId);
  final completer = Completer<bool>();
  final storageArea = _getStorageArea(type.persistence);
  storageArea.remove(
    [storageKey],
    allowInterop(() {
      debugLog('Removed object.', prefix: storageKey);
      completer.complete(true);
    }),
  );
  return completer.future;
}

void interceptStorageChange<T>({
  required Object storageObj,
  required StorageObject expectedType,
  required void Function(T? storageObj) changeHandler,
  int? tabId,
}) {
  try {
    final expectedStorageKey = _createStorageKey(expectedType, tabId);
    final isExpected = hasProperty(storageObj, expectedStorageKey);
    if (!isExpected) return;

    final objProp = getProperty(storageObj, expectedStorageKey);
    final json = getProperty(objProp, 'newValue') as String?;
    T? decodedObj;
    if (json == null || T == String) {
      decodedObj = json as T?;
    } else {
      decodedObj = serializers.deserialize(jsonDecode(json)) as T?;
    }
    debugLog('Intercepted $expectedStorageKey change: $json');
    return changeHandler(decodedObj);
  } catch (error) {
    debugError(
      'Error intercepting storage object with type $expectedType: $error',
    );
  }
}

StorageArea _getStorageArea(Persistence persistence) {
  // MV2 extensions don't have access to session storage:
  if (!isMV3) return chrome.storage.local;

  switch (persistence) {
    case Persistence.acrossSessions:
      return chrome.storage.local;
    case Persistence.sessionOnly:
      return chrome.storage.session;
  }
}

String _createStorageKey(StorageObject type, int? tabId) {
  if (tabId == null) return type.name;
  return '$tabId-${type.name}';
}
