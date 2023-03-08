// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:html';

void main() {
  print('Initial Print');

  registerExtension('ext.print', (_, __) async {
    print('Hello World');
    return ServiceExtensionResponse.result(json.encode({'success': true}));
  });
  document.body!.append(SpanElement()..text = 'Hello World!!');

  var count = 0;
  Timer.periodic(const Duration(seconds: 1), (_) {
    final myList = [1, 3, 4];
    final mySet = {1, 3, 4, 5};
    final myOtherSet = {MyClass(1), MyClass(2), MyClass(3)};
    final myRecord = (1, a: 2, 3, b: 4);
    print('Counter is: ${++count}');
  });
}

class MyClass {
  final int _field;
  MyClass(this._field); // Breakpoint: newEnclosedClass

  @override
  String toString() => '$_field';

  bool equals(Object other) {
    return other is MyClass && other.toString() == toString();
  }
}