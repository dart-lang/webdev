// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))
library;

import 'package:dwds/expression_compiler.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'events_common.dart';

void main() {
  final provider = TestSdkConfigurationProvider();
  tearDownAll(provider.dispose);

  testWithDwds(provider: provider, moduleFormat: ModuleFormat.ddc);
}
