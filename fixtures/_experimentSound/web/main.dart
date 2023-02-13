// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:core';
import 'dart:html';

void main() {
  // for evaluation
  Timer.periodic(const Duration(seconds: 1), (_) {
    printSimpleLocal();
    printComplexLocal();
    printNestedLocal();
    printSimpleNamedLocal();
    printComplexNamedLocal();
    printNestedNamedLocal();
  });

  document.body!.appendText('Program is running!');
}

void printSimpleLocal() {
  final record = (true, 3);
  print(record); // Breakpoint: printSimpleLocal
}

void printSimpleNamedLocal() {
  final record = (true, cat: 'Vasya');
  print(record); // Breakpoint: printSimpleNamedLocal
}

void printComplexLocal() {
  final record = (true, 3, {'a': 1, 'b': 5});
  print(record); // Breakpoint: printComplexLocal
}

void printComplexNamedLocal() {
  final record = (true, 3, array: {'a': 1, 'b': 5});
  print(record); // Breakpoint: printComplexNamedLocal
}

void printNestedLocal() {
  final record = (true, (false, 5));
  print(record); // Breakpoint: printNestedLocal
}

void printNestedNamedLocal() {
  final record = (true, inner: (false, 5));
  print(record); // Breakpoint: printNestedNamedLocal
}

