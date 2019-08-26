// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An example with more complicated scope

import 'dart:async';
import 'dart:html';

final libraryPublicFinal = MyTestClass();

final _libraryPrivateFinal = 1;
Object libraryNull;
var libraryPublic = ['library', 'public', 'variable'];

var _libraryPrivate = ['library', 'private', 'variable'];

void main() async {
  var local = 'local in main';
  var intLocalInMain = 42;
  var testClass = MyTestClass();
  Object localThatsNull;

  String nestedFunction(String parameter) {
    var another = int.tryParse(parameter);
    return '$local: parameter, $another';
  }

  dynamic nestedWithClosure(String banana) {
    return () => '$local + $banana';
  }

  Timer.periodic(Duration(seconds: 1), (Timer t) {
    var ticks = t.tick;
    // ignore: unused_local_variable, prefer_typing_uninitialized_variables
    var closureLocal;
    libraryPublicFinal.printCount();
    print('ticking... $ticks (the answer is $intLocalInMain)');
    print(nestedFunction('$ticks ${testClass.message}'));
    print(localThatsNull);
    print(libraryNull);
    var f = testClass.methodWithVariables();
    print(f('parameter'));
  });

  document.body.append(SpanElement()..text = 'Exercising some scopes');
  window.console.debug('Page Ready');
  print(_libraryPrivateFinal);
  print(_libraryPrivate);
  print(nestedFunction(_libraryPrivate.first));
  print(nestedWithClosure(_libraryPrivate.first)());
}

String libraryFunction(String arg) {
  print('calling a library function with $arg');
  var concat = 'some constant plus $arg plus whatever';
  print(concat);
  return concat;
}

class MyTestClass {
  final String message;

  String notFinal;

  MyTestClass({this.message = 'world'}) {
    myselfField = this;
  }

  String hello() => message;

  String Function(String) methodWithVariables() {
    var local = '$message + something';
    print(local);
    return (String parameter) {
      // Be sure to use a field from this, so it isn't entirely optimized away.
      var closureLocalInsideMethod = '$message/$local/$parameter';
      print(closureLocalInsideMethod);
      return closureLocalInsideMethod;
    };
  }

  //ignore: avoid_returning_this
  MyTestClass get myselfGetter => this;

  MyTestClass myselfField;

  var count = 0;

  // An easy location to add a breakpoint.
  void printCount() {
    print('The count is ${++count}');
    libraryFunction('abc');
  }

  // ignore: unused_field
  final _privateField = 'a private field';

  @override
  String toString() => 'A test class with message $message';

  Function closure = someFunction;
}

Function someFunction() => null;
