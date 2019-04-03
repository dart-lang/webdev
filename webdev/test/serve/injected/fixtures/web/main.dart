// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:developer';
import 'dart:html';

void main() {
  document.body.appendText('Hello World!!');

  registerExtension('ext.flutter.disassemble', (_, __) async {
    document.body.appendText('start disassemble ');
    await Future.delayed(Duration(seconds: 1));
    document.body.appendText('end disassemble ');
    return ServiceExtensionResponse.result('{}');
  });
}
