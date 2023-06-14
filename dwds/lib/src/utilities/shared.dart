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

void safeUnawaited(
  Future<void> future, {
  void Function(dynamic, StackTrace)? onError,
}) {
  onError ??= (error, stackTrace) =>
      _logger.warning('Error in unawaited Future:', error, stackTrace);
  unawaited(future.catchError(onError));
}

/// Throws an [RPCError] if the [asyncCallback] has an exception.
Future<T> wrapInErrorHandlerAsync<T>(
  String command,
  Future<T> Function() asyncCallback,
) {
  return asyncCallback().catchError((error) {
    if (error is RPCError) {
      throw error;
    }
    throw RPCError(
      command,
      RPCErrorKind.kInternalError.code,
      'Unexpected DWDS error for $command: $error',
    );
  });
}
