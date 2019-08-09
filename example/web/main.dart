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
  document.body.append(SpanElement()..text = 'Hello World!!');

  var count = 0;
  var a = 0;
  var z = 0;
  var b = 0;
  Timer.periodic(Duration(seconds: 1), (_) {
    var foo = Foo(5);
    print('Counter is: ${++count} $foo $a $b $z');
  });
}

class Foo {
  int something;
  Foo(this.something);
}
