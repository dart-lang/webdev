// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@JS()
library debugger_panel;

import 'dart:html';

import 'package:js/js.dart';

import 'debug_session.dart';
import 'logger.dart';
import 'utils.dart';

void main() async {
  _registerListeners();
}

void _registerListeners() {
  final launchDebuggerButton = document.getElementById('launchDebuggerButton') as ButtonElement;
  launchDebuggerButton.addEventListener('click', _launchDebugger);
}

void _launchDebugger(Event _) async {
  final dartAppTab = await getActiveTab();
  if (dartAppTab != null) {
    attachDebugger(dartAppTab.id);
  } else {
    debugWarn('Could not get current tab');
  }
}