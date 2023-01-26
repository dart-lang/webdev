// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:core';
import 'dart:html';

void main() {
  // for evaluation
  Timer.periodic(const Duration(seconds: 1), (_) {
    printLocal();
  });

  document.body!.appendText('Program is running!');
}

void printLocal() {
  final record = (true, 3);
  print(record); // Breakpoint: printLocal
}

