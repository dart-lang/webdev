// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:logging/logging.dart';
import 'package:vm_service/vm_service.dart';

VMRef toVMRef(VM vm) => VMRef(name: vm.name);

int _nextId = 0;
String createId() {
  _nextId++;
  return '$_nextId';
}

final _logger = Logger('Utilities');

void safeUnawaited(Future<void> future) {
  unawaited(future.catchError((error, stackTrace) {
    _logger.warning('Error in unawaited Future:', error, stackTrace);
  }));
}
