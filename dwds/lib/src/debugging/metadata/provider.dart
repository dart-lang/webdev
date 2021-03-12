// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

// @dart = 2.9

import 'dart:async';
import 'dart:convert';

import 'package:async/async.dart';
import 'package:logging/logging.dart';

import '../../readers/asset_reader.dart';
import 'module_metadata.dart';

/// A provider of metadata in which data is collected through DDC outputs.
class MetadataProvider {
  final AssetReader _assetReader;
  final _logger = Logger('MetadataProvider');
  final String entrypoint;
  bool _soundNullSafety;
  final List<String> _libraries = [];
  final Map<String, String> _scriptToModule = {};
  final Map<String, String> _moduleToSourceMap = {};
  final Map<String, String> _modulePathToModule = {};
  final Map<String, String> _moduleToModulePath = {};
  final Map<String, List<String>> _scripts = {};
  final _metadataMemoizer = AsyncMemoizer();

  MetadataProvider(this.entrypoint, this._assetReader)
      : _soundNullSafety = false;

  /// A sound null safety mode for the whole app.
  ///
  /// All libraries have to agree on null safety mode.
  Future<bool> get soundNullSafety async {
    await _initialize();
    return _soundNullSafety;
  }

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

  /// A list of module ids
  ///
  /// Example:
  ///
  /// [
  ///   web/main,
  ///   web/foo/bar
  /// ]
  ///
  Future<List<String>> get modules async {
    await _initialize();
    return _moduleToModulePath.keys.toList();
  }

  Future<void> _initialize() async {
    await _metadataMemoizer.runOnce(() async {
      var hasSoundNullSafety = true;
      var hasUnsoundNullSafety = true;
      // The merged metadata resides next to the entrypoint.
      // Assume that <name>.bootstrap.js has <name>.ddc_merged_metadata
      if (entrypoint.endsWith('.bootstrap.js')) {
        _logger.info('Loading debug metadata...');
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
              hasUnsoundNullSafety &= !metadata.soundNullSafety;
              hasSoundNullSafety &= metadata.soundNullSafety;
              _logger
                  .fine('Loaded debug metadata for module: ${metadata.name}');
            } catch (e) {
              _logger.warning('Failed to read metadata: $e');
              rethrow;
            }
          }
          if (!hasSoundNullSafety && !hasUnsoundNullSafety) {
            throw Exception('Metadata contains modules with mixed null safety');
          }
          _soundNullSafety = hasSoundNullSafety;
        }
        _logger.info('Loaded debug metadata '
            '(${_soundNullSafety ? "" : "no "}sound null safety)');
      }
    });
  }

  void _addMetadata(ModuleMetadata metadata) {
    _moduleToSourceMap[metadata.name] = metadata.sourceMapUri;
    _modulePathToModule[metadata.moduleUri] = metadata.name;
    _moduleToModulePath[metadata.name] = metadata.moduleUri;

    for (var library in metadata.libraries.values) {
      if (library.importUri.startsWith('file:/')) {
        throw AbsoluteImportUriException(library.importUri);
      }
      _libraries.add(library.importUri);
      _scripts[library.importUri] = [];

      _scriptToModule[library.importUri] = metadata.name;
      for (var path in library.partUris) {
        _scripts[library.importUri].add(path);
      }
    }
  }
}

class AbsoluteImportUriException implements Exception {
  final String importUri;
  AbsoluteImportUriException(this.importUri);

  @override
  String toString() => "AbsoluteImportUriError: '$importUri'";
}
