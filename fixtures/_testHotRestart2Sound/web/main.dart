// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:core';
import 'dart:html';

import 'package:_test_hot_restart1/library1.dart';
import 'package:_test_hot_restart2/library2.dart';

void main() {
  document.body!.appendText('Program is running!\n');
  document.body!.appendText(value1 == value2
      ? 'ConstantEqualitySuccess\n'
      : 'ConstantEqualityFailure\n');
}
