// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A library that we can import.
library test_deferred_library;

void deferredPrintLocal() {
  print('hello from deferred library'); // Breakpoint: DeferredPrintLocal
}
