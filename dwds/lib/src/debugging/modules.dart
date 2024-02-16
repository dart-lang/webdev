// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async/async.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:logging/logging.dart';

/// Tracks modules for the compiled application.
class Modules {
  final _logger = Logger('Modules');
  final String _root;

  // The Dart server path to containing module.
  final _sourceToModule = <String, String>{};

  // The Dart server path to library import uri
  final _sourceToLibrary = <String, Uri>{};

  // The Dart server path to resolved uri aka "file uri".
  final _sourceToResolvedUri = <String, Uri>{};

  var _moduleMemoizer = AsyncMemoizer<void>();

  final Map<String, String> _libraryToModule = {};

  late String _entrypoint;

  Modules(this._root);

  /// Initializes the mapping from source to module.
  ///
  /// Intended to be called multiple times throughout the development workflow,
  /// e.g. after a hot-reload.
  void initialize(String entrypoint) {
    // We only clear the source to module mapping as script IDs may persist
    // across hot reloads.
    _sourceToModule.clear();
    _sourceToLibrary.clear();
    _sourceToResolvedUri.clear();
    _libraryToModule.clear();
    _moduleMemoizer = AsyncMemoizer();
    _entrypoint = entrypoint;
  }

  /// Returns the containing module for the provided Dart server path.
  Future<String?> moduleForSource(String serverPath) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToModule[serverPath];
  }

  /// Returns the containing library importUri for the provided Dart server path.
  Future<Uri?> libraryForSource(String serverPath) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToLibrary[serverPath];
  }

  /// Returns the resolived uri (or file uri) for the provided Dart server path.
  Future<Uri?> resolvedUriForSource(String serverPath) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToResolvedUri[serverPath];
  }

  Future<String?> moduleForLibrary(String libraryUri) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _libraryToModule[libraryUri];
  }

  // Returns mapping from server paths to library paths
  Future<Map<String, String>> modules() async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToModule;
  }

  /// Initializes [_sourceToModule], [_sourceToLibrary] and
  /// [_sourceToResolvedUri].
  Future<void> _initializeMapping() async {
    final provider =
        globalToolConfiguration.loadStrategy.metadataProviderFor(_entrypoint);

    final libraryToScripts = await provider.scripts;
    final scriptToModule = await provider.scriptToModule;

    for (var library in libraryToScripts.keys) {
      final scripts = libraryToScripts[library]!;
      final libraryServerPath = library.startsWith('dart:')
          ? library
          : DartUri(library, _root).serverPath;

      if (scriptToModule.containsKey(library)) {
        final module = scriptToModule[library]!;

        _sourceToModule[libraryServerPath] = module;
        _sourceToLibrary[libraryServerPath] = Uri.parse(library);
        final resolvedUri = DartUri.uriToResolvedUri[library];
        if (resolvedUri != null) {
          _sourceToResolvedUri[libraryServerPath] = Uri.parse(resolvedUri);
        }
        _libraryToModule[library] = module;

        for (var script in scripts) {
          final scriptServerPath = script.startsWith('dart:')
              ? script
              : DartUri(script, _root).serverPath;
          final resolvedUri = DartUri.uriToResolvedUri[script];

          _sourceToModule[scriptServerPath] = module;
          _sourceToLibrary[scriptServerPath] = Uri.parse(library);
          if (resolvedUri != null) {
            _sourceToResolvedUri[scriptServerPath] = Uri.parse(resolvedUri);
          }
        }
      } else {
        _logger.warning('No module found for library $library');
      }
    }
  }
}
