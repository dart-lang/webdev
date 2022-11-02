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

enum StorageObject {
  devToolsOpener;

  String get keyName {
    switch (this) {
      case StorageObject.devToolsOpener:
        return 'devToolsOpener';
    }
  }
}

Future<bool> setStorageObject<T>({
  required StorageObject type,
  required T value,
  void Function()? callback,
}) {
  final storageKey = type.keyName;
  final json = jsonEncode(serializers.serialize(value));
  final storageObj = <String, String>{storageKey: json};
  final completer = new Completer<bool>();
  chrome.storage.local.set(jsify(storageObj), allowInterop(() {
    if (callback != null) {
      callback();
    }
    completer.complete(true);
  }));
  return completer.future;
}

Future<T?> fetchStorageObject<T>({required StorageObject type}) {
  final storageKey = type.keyName;
  final completer = new Completer<T?>();
  chrome.storage.local.get([storageKey], allowInterop((Object storageObj) {
    final json = getProperty(storageObj, storageKey) as String?;
    if (json == null) {
      completer.complete(null);
    } else {
      final value = serializers.deserialize(jsonDecode(json)) as T;
      completer.complete(value);
    }
  }));
  return completer.future;
}
