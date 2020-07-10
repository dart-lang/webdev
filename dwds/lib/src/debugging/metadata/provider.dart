// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:convert';

import '../../../dwds.dart';
import '../../loaders/strategy.dart';
import 'module_metadata.dart';

/// Provider of DDC meta data for a compiled application.
abstract class MetadataProvider {
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
  Future<List<String>> get libraries;

  /// A map of script to corresponding parts.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///     [
  ///       org-dartlang-app:///web/a.part.dart,
  ///       org-dartlang-app:///web/b.part.dart,
  ///     ]
  ///  }
  ///
  Future<Map<String, List<String>>> get scripts;

  /// A map of script to containing module.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   web/main
  /// }
  ///
  Future<Map<String, String>> get scriptToModule;

  /// Initializes the provider for the given Dart application entrypoint.
  Future<void> initialize(String entrypointPath);
}

/// A provider of metadata in which data is collected through DDC outputs.
class FileMetadataProvider implements MetadataProvider {
  final AssetReader _assetReader;
  final LoadStrategy _loadStrategy;

  final List<String> _libraries = [];
  final Map<String, String> _scriptToModule = {};
  final Map<String, List<String>> _scripts = {};

  FileMetadataProvider(this._assetReader, this._loadStrategy);

  @override
  Future<List<String>> get libraries {
    return Future.value(_libraries);
  }

  @override
  Future<Map<String, String>> get scriptToModule =>
      Future.value(_scriptToModule);

  @override
  Future<Map<String, List<String>>> get scripts => Future.value(_scripts);

  @override
  Future<void> initialize(String entrypoint) async {
    // The merged metadata resides next to the entrypoint.
    // Assume that <name>.bootstrap.js has <name>.ddc_merged_metadata
    if (entrypoint.endsWith('.bootstrap.js')) {
      var serverPath =
          entrypoint.replaceAll('.bootstrap.js', '.ddc_merged_metadata');
      var merged = await _assetReader.metadataContents(serverPath);
      if (merged != null) {
        // read merged metadata if exists
        for (var contents in merged.split('\n')) {
          try {
            _addMetadata(contents);
          } catch (_) {}
        }
      }
    }
  }

  void _addMetadata(String contents) {
    if (contents == null) return;

    var moduleJson = json.decode(contents);
    var metadata = ModuleMetadata.fromJson(moduleJson as Map<String, dynamic>);

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
