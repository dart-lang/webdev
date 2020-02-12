// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';

import 'strategy.dart';

/// A load strategy for the legacy module system.
class LegacyStrategy extends LoadStrategy {
  @override
  final ReloadConfiguration reloadConfiguration;

  LegacyStrategy(this.reloadConfiguration);

  @override
  String get id => 'legacy';

  @override
  String get loadLibrariesSnippet =>
      'for(let module of dart_library.libraries()) {\n'
      'dart_library.import(module)[module];\n'
      '}\n'
      'let libs = $loadModuleSnippet("dart_sdk").dart.getLibraries();\n';

  @override
  String get loadModuleSnippet => 'dart_library.import';

  @override
  Future<String> bootstrapFor(String entrypoint) async => '';

  @override
  Handler get handler => (request) => null;
}
