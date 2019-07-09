// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// An example with more complicated scope

import 'dart:async';
import 'dart:html';

final libraryPublicFinal = MyTestClass();

final _libraryPrivateFinal = 1;

var libraryPublic = ['library', 'public', 'variable'];

var _libraryPrivate = ['library', 'private', 'variable'];

void main() async {
  var local = 'local in main';
  var intLocalInMain = 42;
  var testClass = MyTestClass();

  String nestedFunction(String parameter) {
    var another = int.tryParse(parameter);
    return '$local: parameter, $another';
  }

  dynamic nestedWithClosure(String banana) {
    return () => '$local + $banana';
  }

  Timer.periodic(Duration(seconds: 1), (Timer t) {
    var ticks = t.tick;
    libraryPublicFinal.printCount();
    print('ticking... $ticks (the answer is $intLocalInMain)');
    print(nestedFunction('$ticks ${testClass.message}'));
  });

  document.body.append(SpanElement()..text = 'Exercising some scopes');
  window.console.debug('Page Ready');
  print(_libraryPrivateFinal);
  print(_libraryPrivate);
  print(nestedFunction(_libraryPrivate.first));
  print(nestedWithClosure(_libraryPrivate.first)());
  testClass.methodWithVariables();
}

class MyTestClass {
  final String message;

  String notFinal;

  MyTestClass({this.message = 'world'});

  String hello() => message;

  String methodWithVariables() {
    var local = '$message + something';
    print(local);
    return local;
  }

  var count = 0;

  // An easy location to add a breakpoint.
  void printCount() {
    print('The count is ${++count}');
  }
}
