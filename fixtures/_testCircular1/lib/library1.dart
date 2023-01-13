// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore: illegal_language_version_override
// @dart=2.9

/// A library that we can import.
library _test_circular1;

import 'package:_test_circular2/library2.dart';

String concatenate(String a, String b) {
  return '$a$b'; // Breakpoint: Concatenate
}

void printGlobal() {
  print(globalValue);
}
