// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'package:test/test.dart';

import '../test_utils.dart';
import 'app_domain_common.dart';

void main() {
  appDomainTests(testRunner: TestRunner());
}
