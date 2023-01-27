// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:html';

void main() {
  print('Initial Print');

  //var r = (true, 3);
  //print(r);
  //print(r is (bool, int));

  registerExtension('ext.print', (_, __) async {
    print('Hello World');
    return ServiceExtensionResponse.result(json.encode({'success': true}));
  });
  document.body?.append(SpanElement()..text = 'Hello World!!');

  var count = 0;
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('Counter is: ${++count}'); // Breakpoint: printCounter
  });
}
