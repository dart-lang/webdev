// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../dwds.dart' show ChromeDebugException;
import '../utilities/wrapped_service.dart';

typedef LogWriter = void Function(Level, String);

VMRef toVMRef(VM vm) => VMRef()..name = vm.name;

int _nextId = 0;
String createId() {
  _nextId++;
  return '$_nextId';
}

/// Returns a port that is probably, but not definitely, not in use.
///
/// This has a built-in race condition: another process may bind this port at
/// any time after this call has returned.
Future<int> findUnusedPort() async {
  int port;
  ServerSocket socket;
  try {
    socket =
        await ServerSocket.bind(InternetAddress.loopbackIPv6, 0, v6Only: true);
  } on SocketException {
    socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  }
  port = socket.port;
  await socket.close();
  return port;
}

/// Throws an [ExceptionDetails] object if `exceptionDetails` is present on the
/// result.
void handleErrorIfPresent(WipResponse response,
    {String evalContents, Object additionalDetails}) {
  if (response == null) return;
  if (response.result.containsKey('exceptionDetails')) {
    throw ChromeDebugException(
        response.result['exceptionDetails'] as Map<String, dynamic>,
        evalContents: evalContents,
        additionalDetails: additionalDetails);
  }
}
