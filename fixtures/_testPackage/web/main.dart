// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore: illegal_language_version_override
// @dart=2.9

import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:developer';
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

void main() {
  var count = 0;
  // For setting breakpoints.
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('Count is: ${++count}');
    print(testLibraryValue);
    print(testPartLibraryValue);
  });

  // for evaluation
  var extensionId = 0;
  Timer.periodic(const Duration(seconds: 1), (_) {
    printLocal();
    printFieldFromLibraryClass(); // Breakpoint: callPrintFieldFromLibraryClass
    printFieldFromLibraryPartClass();
    printFieldMain();
    printGlobal();
    printFromTestLibrary();
    printFromTestLibraryPart();
    printFromTestPackage();
    printCallExtension();
    printLoopVariable();
    printObjectMultiLine(); // Breakpoint: callPrintObjectMultiLine
    printNestedObjectsMultiLine(); // Breakpoint: callPrintEnclosingFunctionMultiLine
    printStream(); // Breakpoint: callPrintStream
    printList();
    printMap();
    printSet();
    printFrame2();
    printLargeScope();
    // For testing evaluation in async JS frames.
    registerUserExtension(extensionId++);
  });

  document.body.appendText(concatenate('Program', ' is running!'));
}

void registerUserExtension(int id) async {
  registerExtension('ext.extension$id', (_, __) async {
    print('Hello World from extension$id');
    return ServiceExtensionResponse.result(json.encode({'success': true}));
  });
}

void printLocal() {
  var local = 42;
  print('Local is: $local'); // Breakpoint: printLocal
}

void printFieldFromLibraryClass() {
  var instance = TestLibraryClass(1, 2); // Breakpoint: createLibraryObject
  print('$instance'); // Breakpoint: printFieldFromLibraryClass
}

void printFieldFromLibraryPartClass() {
  var instance = TestLibraryPartClass(1, 2);
  print('$instance'); // Breakpoint: printFieldFromLibraryPartClass
}

void printFieldMain() {
  var instance = MainClass(2, 1);
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
  printEnclosingObject(// Breakpoint: printEnclosingFunctionMultiLine
      EnclosingClass(// Breakpoint: printEnclosingObjectMultiLine
          EnclosedClass(0) // Breakpoint: printNestedObjectMultiLine
          ));
}

void printObjectMultiLine() {
  print(// Breakpoint: printMultiLine
      // Breakpoint: Do not remove, will break callstack tests!
      createObject() // Breakpoint: printObjectMultiLine
        ..initialize());
}

void printEnclosingObject(EnclosingClass o) {
  print(o); // Breakpoint: printEnclosingObject
}

void printStream() {
  var controller = StreamController<int>();
  var stream = controller.stream.asBroadcastStream();
  var subscription = stream.listen(print);
  controller.sink.add(0);
  subscription.cancel(); // Breakpoint: printStream
}

void printList() {
  final list = [0, 1, 2];
  print(list); // Breakpoint: printList
}

void printMap() {
  final map = {'a': 1, 'b': 2, 'c': 3};
  print(map); // Breakpoint: printMap
}

void printSet() {
  final mySet = {1, 4, 5, 7};
  print(mySet); // Breakpoint: printSet
}

ClassWithMethod createObject() {
  return ClassWithMethod(0); // Breakpoint: createObjectWithMethod
}

void printFrame2() {
  final local2 = 2;
  print(local2);
  printFrame1();
}

void printFrame1() {
  final local1 = 1;
  print(local1); // Breakpoint: printFrame1
}

void printLargeScope() {
  var t0 = 0;
  var t1 = 1;
  var t2 = 2;
  var t3 = 3;
  var t4 = 4;
  var t5 = 5;
  var t6 = 6;
  var t7 = 7;
  var t8 = 8;
  var t9 = 9;
  var t10 = 10;
  var t11 = 11;
  var t12 = 12;
  var t13 = 13;
  var t14 = 14;
  var t15 = 15;
  var t16 = 16;
  var t17 = 17;
  var t18 = 18;
  var t19 = 19;

  print('$t0 $t1, $t2, $t3, $t4, $t5, $t6, $t7, $t8, $t9, $t10, '
      '$t11, $t12, $t13, $t14, $t15, $t16, $t17, $t18, $t19'); // Breakpoint: printLargeScope
}

class MainClass {
  final int field;
  final int _field;
  MainClass(this.field, this._field); // Breakpoint: newMainClass

  @override
  String toString() => '$field, $_field'; // Breakpoint: toStringMainClass
}

class EnclosedClass {
  final int _field;
  EnclosedClass(this._field); // Breakpoint: newEnclosedClass

  @override
  String toString() => '$_field';
}

class ClassWithMethod {
  final int _field;
  ClassWithMethod(this._field);

  void initialize() {}

  @override
  String toString() => '$_field';
}

class EnclosingClass {
  final EnclosedClass _field;
  EnclosingClass(this._field); // Breakpoint: newEnclosingClass

  @override
  String toString() => '$_field';
}
