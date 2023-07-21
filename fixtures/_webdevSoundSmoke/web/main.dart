// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:html';

class A {}

class B extends A {}

extension AExt on A {
  void foo() {
    print('AExt');
  }
}

extension BExt on B {
  void foo() {
    print('BExt');
  }
}

class Node {
  Node? next;
  Node([Node? n]) : next = n;

  static Node? create() {
    return Node(Node());
  }
}

void main() {
  print('Initial Print');

  registerExtension('ext.print', (_, __) async {
    print('Hello World');
    return ServiceExtensionResponse.result(json.encode({'success': true}));
  });
  document.body?.append(SpanElement()..text = 'Hello World!!');

  Timer.periodic(const Duration(seconds: 1), (_) {
    A a = B();
    a.foo(); // vm: 'BExt' (incorrect), web: 'AExt' (correct)
    if (a is B) {
      a.foo(); // vm: 'BExt' (correct), web: 'AExt' (incorrect)
    }
    Node? node = Node.create();
    for (var n = node; n != null; n = n.next) {
      print('hello');
    }
  });
}

// current eval function for web
// Gives incorrect result of 'AExt;
dynamic evalCurrent(A a) {
  return a.foo();
}

// current eval function for vm
// Gives incorrect result of 'AExt;
dynamic evalCurrentVM(dynamic a) {
  return a.foo();
}

dynamic evalSuggested(B a) {
  return a.foo();
}

// for null safety
void nullSafetyExample(Node? node) {
  // hovering over 'n.next' gives a compilation error because we pass 'Node?'
  // type for n to the eval function
  for (var n = node; n != null; n = n.next) {
    print('hello');
  }
}

// What needs to be done:
// For expression evaluation:
// - collect correct current types for the eval function arguments and pass them to the eval function
// 
// For variable display of views:
// option 1: implement in dap
// - for each view getter of the object, eval '(object as View).getter'
// 
// option 2: implement in vm_service protocol (might be faster)
// - vm service protocol new API
//   getObjectView(isolateId, objectId, typeId);
//   returns a fake object of type with 'typeId' and getters filled with eval '(object as View).getter'
// - backends to implement this (can ddc add a runtime function for this to skip expression compilation?)