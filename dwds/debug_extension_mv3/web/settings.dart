// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library settings;

import 'dart:async';
import 'dart:html';

import 'package:js/js.dart';

import 'data_types.dart';
import 'storage.dart';

void main() {
  _registerListeners();
}

void _registerListeners() {
  document.addEventListener('DOMContentLoaded', _updateSettingsFromStorage);
  final saveButton = document.getElementById('saveButton') as ButtonElement;
  saveButton.addEventListener('click', _saveSettingsToStorage);
}

void _updateSettingsFromStorage(Event _) async {
  final devToolsOpener = await fetchStorageObject<DevToolsOpener>(
      type: StorageObject.devToolsOpener);
  final openInNewWindow = devToolsOpener?.newWindow ?? false;
  _getRadioButton('windowOpt').checked = openInNewWindow;
  _getRadioButton('tabOpt').checked = !openInNewWindow;
}

void _saveSettingsToStorage(Event event) async {
  event.preventDefault();
  _maybeHideSavedMsg();
  final form = document.querySelector("form") as FormElement;
  final data = FormData(form);
  final devToolsOpenerValue = data.get('devToolsOpener') as String;
  await setStorageObject<DevToolsOpener>(
      type: StorageObject.devToolsOpener,
      value: DevToolsOpener(
          (b) => b..newWindow = devToolsOpenerValue == 'window'));
  _showSavedMsg();
}

void _showSavedMsg() {
  final snackbar = document.getElementById('savedSnackbar');
  if (snackbar == null) return;
  snackbar.classes.add('show');
  Timer(Duration(seconds: 3), () {
    _maybeHideSavedMsg();
  });
}

void _maybeHideSavedMsg() {
  final snackbar = document.getElementById('savedSnackbar');
  if (snackbar == null) return;
  snackbar.classes.remove('show');
}

RadioButtonInputElement _getRadioButton(String id) {
  return document.getElementById(id) as RadioButtonInputElement;
}
