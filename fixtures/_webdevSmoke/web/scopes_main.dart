// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

/// An example with more complicated scope
import 'dart:async';
import 'dart:collection';

final libraryPublicFinal = MyTestClass();

final _libraryPrivateFinal = 1;
Object libraryNull;
var libraryPublic = <String>['library', 'public', 'variable'];
var notAList = NotReallyAList();

var _libraryPrivate = ['library', 'private', 'variable'];

var identityMap = <String, int>{};

var map = <Object, Object>{};

void staticFunction(int formal) {
  print(formal); // Breakpoint: staticFunction
}

void main() async {
  print('Initial print from scopes app');
  var local = 'local in main';
  var intLocalInMain = 42;
  var testClass = MyTestClass();
  Object localThatsNull;
  identityMap['a'] = 1;
  identityMap['b'] = 2;
  map['a'] = [1, 2, 3];
  map['b'] = 'something';
  notAList.add(7);

  String nestedFunction<T>(T parameter, Object aClass) {
    var another = int.tryParse('$parameter');
    return '$local: parameter, $another'; // Breakpoint: nestedFunction
  }

  dynamic nestedWithClosure(String banana) {
    return () => '$local + $banana';
  }

  Timer.periodic(const Duration(seconds: 1), (Timer t) {
    var ticks = t.tick;
    // ignore: unused_local_variable, prefer_typing_uninitialized_variables
    var closureLocal;
    libraryPublicFinal.printCount();
    staticFunction(1);
    print('ticking... $ticks (the answer is $intLocalInMain)');
    print(nestedFunction('$ticks ${testClass.message}', Timer));
    print(localThatsNull);
    print(libraryNull);
    var localList = libraryPublic;
    print(localList);
    localList.add('abc');
    var f = testClass.methodWithVariables();
    print(f('parameter'));
  });

  print(_libraryPrivateFinal);
  print(_libraryPrivate);
  print(nestedFunction(_libraryPrivate.first, Object));
  print(nestedWithClosure(_libraryPrivate.first)());
}

String libraryFunction(String arg) {
  print('calling a library function with $arg');
  var concat = 'some constant plus $arg plus whatever';
  print(concat);
  return concat;
}

class MyTestClass<T> {
  final String message;

  String notFinal;

  MyTestClass({this.message = 'world'}) {
    myselfField = this;
    tornOff = toString;
  }

  String hello() => message;

  String Function(String) methodWithVariables() {
    var local = '$message + something';
    print(local);
    return (String parameter) {
      // Be sure to use a field from this, so it isn't entirely optimized away.
      var closureLocalInsideMethod = '$message/$local/$parameter';
      print(closureLocalInsideMethod);
      return closureLocalInsideMethod; // Breakpoint: nestedClosure
    };
  }

  //ignore: avoid_returning_this
  MyTestClass get myselfGetter => this;

  MyTestClass myselfField;

  var count = 0;

  // An easy location to add a breakpoint.
  void printCount() {
    print('The count is ${++count}');
    libraryFunction('abc'); // Breakpoint: printMethod
  }

  final _privateField = 'a private field';

  // ignore: unused_element
  String privateMethod(String s) => '$s : $_privateField';

  @override
  String toString() => 'A test class with message $message';

  bool equals(Object other) {
    if (other is MyTestClass) return message == other.hello();
    return false;
  }

  Function closure = someFunction;

  String Function() tornOff;
}

Function someFunction() => null;

// ignore: unused_element
int _libraryPrivateFunction(int a, int b) => a + b;

class NotReallyAList extends ListBase {
  final List _internal;

  NotReallyAList() : _internal = [];

  @override
  Object operator [](x) => _internal[x];

  @override
  operator []=(x, y) => _internal[x] = y;

  @override
  int get length => _internal.length;

  @override
  set length(x) => _internal.length = x;
}
