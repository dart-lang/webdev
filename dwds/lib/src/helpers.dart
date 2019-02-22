// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:vm_service_lib/vm_service_lib.dart';

IsolateRef toIsolateRef(Isolate isolate) => IsolateRef()
  ..id = isolate.id
  ..fixedId = isolate.fixedId
  ..name = isolate.name
  ..number = isolate.number;

int _nextId = 0;
String createId() {
  _nextId++;
  return '$_nextId';
}
