// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_test_circular1_sound/library1.dart';

int globalValue = 0;

void testCircularDependencies() {
  print(concatenate('a', 'b')); // Breakpoint: testCircularDependencies
}
