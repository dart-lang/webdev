// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:html';

import 'package:_test/library.dart';
import 'package:_testPackage/test_library.dart';

extension NumberParsing on String {
  int parseInt() {
    var ret = int.parse(this);
    return ret; // Breakpoint: extension
  }
}

void main() {
  var count = 0;
  // For setting breakpoints.
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('Count is: ${++count}');
    print(testLibraryValue);
  });

  // for evaluation
  Timer.periodic(const Duration(seconds: 1), (_) {
    printLocal();
    printField();
    printGlobal();
    printFromTestLibrary();
    printFromTestPackage();
    printCallExtension();
  });

  document.body.appendText(concatenate('Program', ' is running!'));
}

void printLocal() {
  var local = 42;
  print('Local is: $local'); // Breakpoint: printLocal
}

void printField() {
  var instance = TestLibraryClass(1, 2);
  print('$instance'); // Breakpoint: printField
}

void printGlobal() {
  print(testLibraryValue); // Breakpoint: printGlobal
}

void printFromTestPackage() {
  print(concatenate('Hello', ' World'));
}

void printFromTestLibrary() {
  var local = 23;
  print(testLibraryFunction(local));
}

void printCallExtension() {
  var local = '23';
  print(local.parseInt());
}
