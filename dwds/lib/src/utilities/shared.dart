// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/services/chrome_debug_exception.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart'
    as wip;

VMRef toVMRef(VM vm) => VMRef(name: vm.name);

int _nextId = 0;
String createId() {
  _nextId++;
  return '$_nextId';
}

/// Throws an [wip.ExceptionDetails] object if `exceptionDetails` is present on the
/// result.
void handleErrorIfPresent(wip.WipResponse? response, {String? evalContents}) {
  final result = response?.result;
  if (result == null) return;
  if (result.containsKey('exceptionDetails')) {
    throw ChromeDebugException(
      result['exceptionDetails'] as Map<String, dynamic>,
      evalContents: evalContents,
    );
  }
}

/// Returns result contained in the response.
/// Throws an [wip.ExceptionDetails] object if `exceptionDetails` is present on the
/// result or the result is null.
Map<String, dynamic> getResultOrHandleError(wip.WipResponse? response,
    {String? evalContents}) {
  handleErrorIfPresent(response, evalContents: evalContents);
  final result = response?.result?['result'];
  if (result == null) {
    throw ChromeDebugException(
      {'text': 'null result from Chrome Devtools'},
      evalContents: evalContents,
    );
  }
  return result;
}
