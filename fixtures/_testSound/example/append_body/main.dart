// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:developer';
// TODO: https://github.com/dart-lang/webdev/issues/2508
// ignore: deprecated_member_use
import 'dart:html';
import 'dart:js_interop';

@JS('console.log')
external void log(String _);

void main() {
  var count = 0;
  // For setting breakpoints.
  Timer.periodic(const Duration(seconds: 1), (_) {
    print('Count is: ${++count}'); // Breakpoint: printCount
  });

  document.body?.appendText('Hello World!');

  registerExtension('ext.flutter.disassemble', (_, __) async {
    document.body?.appendText('start disassemble ');
    await Future.delayed(const Duration(seconds: 1));
    document.body?.appendText('end disassemble ');
    return ServiceExtensionResponse.result('{}');
  });

  // Wait for this print statement so that we know main is done executing.
  log('main executed');
}
