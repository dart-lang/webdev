// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:core';
import 'dart:html';

import 'package:_test/deferred_library.dart' deferred as d;
import 'package:_test/library.dart';
import 'package:_test_package/test_library.dart';

extension NumberParsing on String {
  int parseInt() {
    var ret = int.parse(this);
    return ret; // Breakpoint: extension
  }
}

void main() async {
  var count = 0;
  // For setting breakpoints.
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('Count is: ${++count}');
    print(testLibraryValue);
    print(testPartLibraryValue);
  });

  // for evaluation
  Timer.periodic(const Duration(seconds: 1), (_) async {
    await asyncMethod();
    printLocal();
    printFieldFromLibraryClass();
    printFieldFromLibraryPartClass();
    printFieldMain();
    printGlobal();
    printFromTestLibrary();
    printFromTestLibraryPart();
    printFromTestPackage();
    printCallExtension();
    printLoopVariable();
    printGeneric<int>(0);
    printNestedObjectsMultiLine();
  });

  document.body?.appendText(concatenate('Program', ' is running!'));
}

Future<int> asyncMethod() async {
  printLocal();
  return 0;
}

void printGeneric<T>(T formal) {
  print(formal);
}

void printLocal() {
  var local = 42;
  print('Local is: $local'); // Breakpoint: printLocal
}

void printFieldFromLibraryClass() {
  var instance = TestLibraryClass(1, 2);
  print('$instance'); // Breakpoint: printFieldFromLibraryClass
}

void printFieldFromLibraryPartClass() {
  var instance = TestLibraryPartClass(1, 2);
  print('$instance'); // Breakpoint: printFieldFromLibraryPartClass
}

void printFieldMain() {
  var instance = MainClass(1);
  print('$instance'); // Breakpoint: printFieldMain
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

void printFromTestLibraryPart() {
  var local = 23;
  print(testLibraryPartFunction(local));
}

void printCallExtension() {
  var local = '23';
  print(local.parseInt());
}

void printLoopVariable() {
  var list = <String>['1'];
  for (var item in list) {
    print(item); // Breakpoint: printLoopVariable
  }
}

Future<void> printDeferred() async {
  d.deferredPrintLocal();
}

void printNestedObjectsMultiLine() {
  print(
    EnclosingMainClass(
      MainClass(0) // Breakpoint: printNestedObjectsMultiLine
    ));
}

class MainClass {
  final int _field;
  MainClass(this._field);

  @override
  String toString() => '$_field';
}

class EnclosingMainClass {
  final MainClass _field;
  EnclosingMainClass(this._field);

  @override
  String toString() => '$_field';
}
