// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:dwds/dwds.dart' show ModuleStrategy;

import '../utilities/wrapped_service.dart';

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

String _fetchModuleStrategy(ModuleStrategy config) {
  switch (config) {
    case ModuleStrategy.legacy:
      return 'dart_library.import';
    case ModuleStrategy.requireJS:
      return 'require';
  }
  throw StateError('Unreachable code');
}

String _loadModule;

String get loadModule => _loadModule;

set globalModuleStrategy(ModuleStrategy moduleStrategy) {
  _loadModule = _fetchModuleStrategy(moduleStrategy);
}
