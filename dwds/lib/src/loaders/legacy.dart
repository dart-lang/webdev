// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shelf/shelf.dart';

import 'strategy.dart';

/// A load strategy for the legacy module system.
class LegacyStrategy extends LoadStrategy {
  @override
  final ReloadConfiguration reloadConfiguration;

  /// Returns the module for the corresponding server path.
  ///
  /// For example:
  ///
  /// /packages/path/path.ddc.js -> packages/path/path
  ///
  final String Function(String sourcePath) _moduleForServerPath;

  /// Returns the server path for the provided module.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc.js
  ///
  final String Function(String module) _serverPathForModule;

  LegacyStrategy(
    this.reloadConfiguration,
    this._moduleForServerPath,
    this._serverPathForModule,
  );

  @override
  Handler get handler => (request) => null;

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
  String loadClientSnippet(String clientScript) =>
      'window.\$dartLoader.forceLoadModule("$clientScript");\n';

  @override
  String moduleForServerPath(String serverPath) =>
      _moduleForServerPath(serverPath);

  @override
  String serverPathForModule(String module) => _serverPathForModule(module);
}
