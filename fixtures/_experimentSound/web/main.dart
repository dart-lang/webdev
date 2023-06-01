// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:core';
import 'dart:html';

void main() {
  // for evaluation
  Timer.periodic(const Duration(seconds: 1), (_) {
    printSimpleLocalRecord();
    printComplexLocalRecord();
    printNestedLocalRecord();
    printSimpleNamedLocalRecord();
    printComplexNamedLocalRecord();
    printNestedNamedLocalRecord();
    print('Patterns'); // Breakpoint: callTestPattern1
    testPattern(['a', 1]);
    testPattern([3.14, 'b']);
    testPattern([0, 1]);
    testPattern2();
  });

  document.body!.appendText('Program is running!');
}

void printSimpleLocalRecord() {
  final record = (true, 3);
  print(record); // Breakpoint: printSimpleLocalRecord
}

void printSimpleNamedLocalRecord() {
  final record = (true, cat: 'Vasya');
  print(record); // Breakpoint: printSimpleNamedLocalRecord
}

void printComplexLocalRecord() {
  final record = (true, 3, {'a': 1, 'b': 5});
  print(record); // Breakpoint: printComplexLocalRecord
}

void printComplexNamedLocalRecord() {
  final record = (true, 3, array: {'a': 1, 'b': 5});
  print(record); // Breakpoint: printComplexNamedLocalRecord
}

void printNestedLocalRecord() {
  final record = (true, (false, 5));
  print(record); // Breakpoint: printNestedLocalRecord
}

void printNestedNamedLocalRecord() {
  final record = (true, inner: (false, 5));
  print(record); // Breakpoint: printNestedNamedLocalRecord
}

String testPattern(Object obj) {
  switch (obj) {
    case [var a, int n] || [int n, var a] when n == 1 && a is String:
      return a.toString(); // Breakpoint: testPatternCase1
    case [double n, var a] || [var a, double n] when (n - 3.14).abs() < 0.001:
      return a.toString(); // Breakpoint: testPatternCase2
    default:
      return 'default'; // Breakpoint: testPatternDefault
  }
}

String testPattern2() {
  final dog = 'Prismo'; 
  final cats = ['Garfield', 'Tom']; // Breakpoint: testPattern2Case1
  final [firstCat, secondCat] = cats;
  print(firstCat); // Breakpoint: testPattern2Case2
  return '$dog, $firstCat, $secondCat';
}
