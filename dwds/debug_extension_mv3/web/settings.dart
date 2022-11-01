// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library settings;

import 'dart:convert';
import 'dart:html';
import 'dart:js_util';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';
import 'web_api.dart';
import 'storage.dart';
import 'data_serializers.dart';
import 'data_types.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  document.addEventListener('DOMContentLoaded', _updateSettingsFromStorage);

  final saveButton = document.getElementById('save');
  if (saveButton != null) {
    saveButton.addEventListener('click', _saveSettingsToStorage);
  }
}

void _updateSettingsFromStorage(Event _) {


}

void _saveSettingsToStorage(Event _) {
  final devToolsOpenerSelect =
      document.getElementById('devToolsOpener') as SelectElement;
  final json = jsonEncode(serializers.serialize(DevToolsOpener(
      (b) => b..newWindow = devToolsOpenerSelect.value == 'window')));
  setStorageObject(type: StorageObject.devToolsOpener, json: json);
}
