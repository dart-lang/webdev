// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library that we can import.
library test_library;

int aVariable = 3;

String concatenate(String a, String b) {
  return '$a$b'; // Breakpoint: Concatenate
}
