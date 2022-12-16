// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:core';
import 'dart:html';

import 'package:_test_package_sound/test_library.dart';
import 'package:_test_sound/deferred_library.dart' deferred as d;
import 'package:_test_sound/library.dart';

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
    printFieldFromLibraryClass(); // Breakpoint: callPrintFieldFromLibraryClass
    printFieldFromLibraryPartClass();
    printFieldMain();
    printGlobal();
    printFromTestLibrary();
    printFromTestLibraryPart();
    printFromTestPackage();
    printCallExtension();
    printLoopVariable();
    printGeneric<int>(0);
    printObjectMultiLine(); // Breakpoint: callPrintObjectMultiLine
    printNestedObjectsMultiLine(); // Breakpoint: callPrintEnclosingFunctionMultiLine
    printStream(); // Breakpoint: callPrintStream
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
  var instance = TestLibraryClass(1, 2); // Breakpoint: createLibraryObject
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
  printEnclosingObject(// Breakpoint: printEnclosingFunctionMultiLine
      EnclosingClass(// Breakpoint: printEnclosingObjectMultiLine
          EnclosedClass(0) // Breakpoint: printNestedObjectMultiLine
          ));
}

void printObjectMultiLine() {
  // TODO(https://github.com/dart-lang/webdev/issues/1831) Tests should not
  // break when this file is formatted.
  // Note: formatting the line below breaks callstack tests.
  print( // Breakpoint: printMultiLine
    createObject() // Breakpoint: printObjectMultiLine
      ..initialize(),
  );
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

ClassWithMethod createObject() {
  return ClassWithMethod(0); // Breakpoint: createObjectWithMethod
}

class MainClass {
  final int _field;
  MainClass(this._field); // Breakpoint: newMainClass

  @override
  String toString() => '$_field';
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
