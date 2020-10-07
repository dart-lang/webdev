// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';

import '../../readers/asset_reader.dart';
import '../../services/expression_compiler_service.dart';
import '../../utilities/shared.dart';
import 'module_metadata.dart';

/// A provider of metadata in which data is collected through DDC outputs.
class MetadataProvider {
  final AssetReader _assetReader;
  final LogWriter _logWriter;
  final String entrypoint;
  final ExpressionCompilerService _compilerService;
  final _libraries = <String>[];
  final _scriptToModule = <String, String>{};
  final _moduleToSourceMap = <String, String>{};
  final _modulePathToModule = <String, String>{};
  final _moduleToModulePath = <String, String>{};
  final _scripts = <String, List<String>>{};
  final _metadataMemoizer = AsyncMemoizer();

  MetadataProvider(this.entrypoint, this._assetReader, this._logWriter,
      this._compilerService);

  /// A list of all libraries in the Dart application.
  ///
  /// Example:
  ///
  ///  [
  ///     dart:web_gl,
  ///     dart:math,
  ///     org-dartlang-app:///web/main.dart
  ///  ]
  ///
  Future<List<String>> get libraries async {
    await _initialize();
    return _libraries;
  }

  /// A map of library uri to dart scripts.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   { web/main.dart  }
  /// }
  ///
  Future<Map<String, List<String>>> get scripts async {
    await _initialize();
    return _scripts;
  }

  /// A map of script to containing module.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   web/main
  /// }
  ///
  Future<Map<String, String>> get scriptToModule async {
    await _initialize();
    return _scriptToModule;
  }

  /// A map of module name to source map path.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   web/main.ddc.js.map
  /// }
  ///
  ///
  Future<Map<String, String>> get moduleToSourceMap async {
    await _initialize();
    return _moduleToSourceMap;
  }

  /// A map of module path to module name
  ///
  /// Example:
  ///
  /// {
  ///   web/main.ddc.js :
  ///   web/main
  /// }
  ///
  Future<Map<String, String>> get modulePathToModule async {
    await _initialize();
    return _modulePathToModule;
  }

  /// A map of module to module path
  ///
  /// Example:
  ///
  /// {
  ///   web/main
  ///   web/main.ddc.js :
  /// }
  ///
  Future<Map<String, String>> get moduleToModulePath async {
    await _initialize();
    return _moduleToModulePath;
  }

  Future<void> _initialize() async {
    await _metadataMemoizer.runOnce(() async {
      // The merged metadata resides next to the entrypoint.
      // Assume that <name>.bootstrap.js has <name>.ddc_merged_metadata
      if (entrypoint.endsWith('.bootstrap.js')) {
        _logWriter(Level.INFO, 'Loading debug metadata...');

        var dependencies = <String, String>{};
        var serverPath =
            entrypoint.replaceAll('.bootstrap.js', '.ddc_merged_metadata');
        var merged = await _assetReader.metadataContents(serverPath);
        if (merged != null) {
          for (var contents in merged.split('\n')) {
            try {
              if (contents == null ||
                  contents.isEmpty ||
                  contents.startsWith('// intentionally empty:')) continue;
              var moduleJson = json.decode(contents);
              var metadata =
                  ModuleMetadata.fromJson(moduleJson as Map<String, dynamic>);
              _addMetadata(metadata);
              // we are assuming the full dill file is located next to .js
              // TODO: This is breakable.
              // Issue: https://github.com/dart-lang/sdk/issues/43684
              dependencies[metadata.name] =
                  metadata.moduleUri.replaceAll('.js', '.full.dill');
              _logWriter(Level.FINEST,
                  'Loaded debug metadata for module: ${metadata.name}');
            } catch (e) {
              _logWriter(
                  Level.WARNING, 'Failed to read metadata: ${e.message}');
              rethrow;
            }
          }
        }

        if (_compilerService != null) {
          var updated = await _compilerService.updateDependencies(dependencies);
          if (!updated) {
            _logWriter(
                Level.WARNING, 'Failed to update dependencies: $dependencies');
          }
        }
        _logWriter(Level.INFO, 'Loaded debug metadata');
      }
    });
  }

  void _addMetadata(ModuleMetadata metadata) {
    _moduleToSourceMap[metadata.name] = metadata.sourceMapUri;
    _modulePathToModule[metadata.moduleUri] = metadata.name;
    _moduleToModulePath[metadata.name] = metadata.moduleUri;

    for (var library in metadata.libraries.values) {
      _libraries.add(library.importUri);
      _scripts[library.importUri] = [];

      _scriptToModule[library.importUri] = metadata.name;
      for (var path in library.partUris) {
        _scripts[library.importUri].add(path);
      }
    }
  }
}
