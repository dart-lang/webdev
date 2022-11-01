// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library settings;

import 'dart:html';
import 'dart:js_util';
import 'package:js/js.dart';

import 'chrome_api.dart';
import 'messaging.dart';
import 'web_api.dart';

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

void _updateSettingsFromStorage(Event event) {

}

void _saveSettingsToStorage(Event event) {
  final devToolsOpener = document.getElementById('devToolsOpener') as SelectElement;
  final openInNewWindow = devToolsOpener.value == 'window';


}