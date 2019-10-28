// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../dwds.dart' show ChromeDebugException, ModuleStrategy;
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

ModuleStrategy globalModuleStrategy;
String get loadModule => _fetchModuleStrategy(globalModuleStrategy);

String get getLibraries {
  var expression = '';
  if (globalModuleStrategy == ModuleStrategy.legacy) {
    expression += 'for(let module of dart_library.libraries()) {\n'
        'dart_library.import(module)[module];\n'
        '}\n';
  }
  return expression +=
      "let libs = $loadModule('dart_sdk').dart.getLibraries();\n";
}

/// Creates a snippet of JS code that initializes a `library` variable that has
/// the actual library object in DDC for [libraryUri].
///
/// In DDC we have module libraries indexed by names of the form
/// 'packages/package/mainFile' with no .dart suffix on the file, or
/// 'directory/packageName/mainFile', also with no .dart suffix, and relative to
/// the serving root, normally /web within the package. These modules have a map
/// from the URI with a Dart-specific scheme (package: or org-dartlang-app:) to
/// the library objects. The [libraryUri] parameter should be one of these
/// Dart-specific scheme URIs, and we set `library` the corresponding library.
String getLibrarySnippet(String libraryUri) => '''
   var sdkUtils = $loadModule('dart_sdk').dart;
   var library = sdkUtils.getLibrary('$libraryUri');
   if (!library) throw 'cannot find library for $libraryUri';
  ''';

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
