// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:dwds/src/debugging/metadata/module_metadata.dart';
import 'package:dwds/src/readers/asset_reader.dart';
import 'package:logging/logging.dart';

/// Interface for fetching and parsing debug metadata emitted by the compiler.
abstract class MetadataLoader {
  /// Loads debug metadata associated with the application [entrypoint].
  ///
  /// Returns a map of module names to their corresponding [ModuleMetadata].
  Future<Map<String, ModuleMetadata>> loadMetadata(String entrypoint);
}

/// Metadata loader that reads merged metadata files.
class MergedMetadataLoader implements MetadataLoader {
  final AssetReader _assetReader;
  final _logger = Logger('MergedMetadataLoader');

  MergedMetadataLoader(this._assetReader);

  @override
  Future<Map<String, ModuleMetadata>> loadMetadata(String entrypoint) async {
    final modules = <String, ModuleMetadata>{};
    // The merged metadata resides next to the entrypoint.
    // Assume that <name>.bootstrap.js has <name>.ddc_merged_metadata
    if (entrypoint.endsWith('.bootstrap.js')) {
      _logger.info('Loading debug metadata...');
      final serverPath = entrypoint.replaceAll(
        '.bootstrap.js',
        '.ddc_merged_metadata',
      );
      final merged = await _assetReader.metadataContents(serverPath);
      if (merged != null) {
        for (final contents in merged.split('\n')) {
          try {
            if (contents.isEmpty ||
                contents.startsWith('// intentionally empty:')) {
              continue;
            }
            final moduleJson = json.decode(contents);
            final metadata = ModuleMetadata.fromJson(
              moduleJson as Map<String, dynamic>,
            );
            final moduleName = metadata.name;
            modules[moduleName] = metadata;
            _logger.fine('Loaded debug metadata for module: $moduleName');
          } catch (e) {
            _logger.warning('Failed to read metadata: $e');
            rethrow;
          }
        }
      }
    }
    return modules;
  }
}
