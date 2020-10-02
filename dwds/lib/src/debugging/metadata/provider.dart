// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';

import '../../readers/asset_reader.dart';
import '../../utilities/shared.dart';
import 'module_metadata.dart';

/// A provider of metadata in which data is collected through DDC outputs.
class MetadataProvider {
  final AssetReader _assetReader;
  final LogWriter _logWriter;
  final Future<bool> Function(Map<String, String> updateDependencies)
      _updateDependencies;

  final List<String> _libraries = [];
  final Map<String, String> _scriptToModule = {};
  final Map<String, String> _moduleToSourceMap = {};
  final Map<String, String> _modulePathToModule = {};
  final Map<String, List<String>> _scripts = {};

  AsyncMemoizer _metadataMemoizer;

  MetadataProvider(this._assetReader, this._updateDependencies, this._logWriter)
      : _metadataMemoizer = AsyncMemoizer<void>();

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
  Future<List<String>> get libraries => Future.value(_libraries);

  /// A map of library uri to dart scripts.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   { web/main.dart  }
  /// }
  ///
  Future<Map<String, List<String>>> get scripts => Future.value(_scripts);

  /// A map of script to containing module.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   web/main
  /// }
  ///
  Future<Map<String, String>> get scriptToModule =>
      Future.value(_scriptToModule);

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
  Future<Map<String, String>> get moduleToSourceMap =>
      Future.value(_moduleToSourceMap);

  /// A map of module path to module name
  ///
  /// Example:
  ///
  /// {
  ///   web/main.ddc.js :
  ///   web/main
  /// }
  ///
  Future<Map<String, String>> get modulePathToModule =>
      Future.value(_modulePathToModule);

  /// Initializes the provider for the given Dart application entrypoint.
  ///
  /// Initialization is done only once, even if called multiple
  /// times, unless [update] is true, in which case the metadata
  /// is re-initialzed.
  ///
  Future<void> initialize(String entrypoint, {bool update = false}) async {
    // make sure we re-initalize on update, for example, on hot restart.
    if (update) {
      _metadataMemoizer = AsyncMemoizer<void>();
    }

    // read metadata if not already read.
    await _metadataMemoizer.runOnce(() async {
      clear();
      // The merged metadata resides next to the entrypoint.
      // Assume that <name>.bootstrap.js has <name>.ddc_merged_metadata
      if (entrypoint.endsWith('.bootstrap.js')) {
        _logWriter(Level.INFO, 'Loading debug metadata...');

        var dependencies = <String, String>{};
        var serverPath =
            entrypoint.replaceAll('.bootstrap.js', '.ddc_merged_metadata');
        var merged = await _assetReader.metadataContents(serverPath);
        if (merged != null) {
          // read merged metadata if exists
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
              // TODO: add location of the full dill to the metadata
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

        // update dependencies in the expression compiler
        if (_updateDependencies != null) {
          if (!(await _updateDependencies(dependencies))) {
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

    for (var library in metadata.libraries.values) {
      _libraries.add(library.importUri);
      _scripts[library.importUri] = [];

      _scriptToModule[library.importUri] = metadata.name;
      for (var path in library.partUris) {
        _scripts[library.importUri].add(path);
      }
    }
  }

  void clear() {
    _moduleToSourceMap.clear();
    _modulePathToModule.clear();
    _libraries.clear();
    _scripts.clear();
    _scriptToModule.clear();
  }
}
