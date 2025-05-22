// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:js_interop';

@JS('console.log')
external void log(String _);

String get mainValue => 'main gen0';

void evaluate() {
  // Use a future as if we come across a breakpoint, evaluating this method
  // would never finish.
  Future.delayed(Duration(milliseconds: 10), printToConsole);
}

void printToConsole() {
  log('$mainValue'); // Breakpoint: callLog
}

final closure = () {
  return 'captured closure gen0'; // Breakpoint: capturedString
};

void main() {}
