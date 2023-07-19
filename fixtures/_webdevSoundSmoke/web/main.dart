// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
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
  document.body?.append(SpanElement()..text = 'Hello World!!');

  var count = 0;
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('Counter is: ${++count}'); // Breakpoint: printCounter

    var b = B();
    print(b);

    var x = () => true;
    print(x);
  });
}

class A {
  int _x1 = 0;
  int x2 = 1;
}

class B extends A {
  int x3 = 2;
  int get x4 => x3;

  int f() => 0;
  static int sf() => 1;

  int Function() f2 = sf;
}
