// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library _test_hot_restart1;

class B {
  final int x;
  const B(this.x);
}

B get value1 => const B(2);
