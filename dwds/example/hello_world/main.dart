// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:html';

void main() async {
  // Travis needs a bit of time here.
  await Future.delayed(Duration(seconds: 5));

  print('hello');
  window.console.error('Expected Error Log');
  throw ArgumentError('Expected Exception!');
}
