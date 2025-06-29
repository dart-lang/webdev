// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:async/async.dart';
import 'package:dwds/src/config/tool_configuration.dart';
import 'package:dwds/src/debugging/debugger.dart';
import 'package:dwds/src/debugging/metadata/provider.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:logging/logging.dart';

/// Tracks modules for the compiled application.
class Modules {
  final _logger = Logger('Modules');
  final String _root;

  // The Dart server path to containing module.
  final _sourceToModule = <String, String>{};

  // Module to Dart server paths.
  final _moduleToSources = <String, Set<String>>{};

  // The Dart server path to library import uri
  final _sourceToLibrary = <String, Uri>{};
  var _moduleMemoizer = AsyncMemoizer<void>();

  final Map<String, String> _libraryToModule = {};

  late String _entrypoint;

  Modules(this._root);

  /// Initializes the mapping from source to module.
  ///
  /// Intended to be called multiple times throughout the development workflow,
  /// e.g. after a hot-reload.
  void initialize(String entrypoint) {
    // TODO(srujzs): Can we do better and only invalidate the sources/modules
    // that were deleted/reloaded? This would require removing the
    // deleted/reloaded libraries/sources/modules from the following maps and
    // then only processing that set in `_initializeMapping`. It's doable, but
    // these calculations are also not that expensive.
    _sourceToModule.clear();
    _moduleToSources.clear();
    _sourceToLibrary.clear();
    _libraryToModule.clear();
    _moduleMemoizer = AsyncMemoizer();
    _entrypoint = entrypoint;
  }

  /// Returns the containing module for the provided Dart server path.
  Future<String?> moduleForSource(String serverPath) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToModule[serverPath];
  }

  /// Returns the Dart server paths for the provided module.
  Future<Set<String>?> sourcesForModule(String module) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _moduleToSources[module];
  }

  /// Returns the containing library importUri for the provided Dart server path.
  Future<Uri?> libraryForSource(String serverPath) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToLibrary[serverPath];
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

  Future<String?> getRuntimeScriptIdForModule(
    String entrypoint,
    String module,
  ) async {
    final serverPath = await globalToolConfiguration.loadStrategy
        .serverPathForModule(entrypoint, module);
    // TODO(srujzs): We should wait until all scripts are parsed before
    // accessing.
    return chromePathToRuntimeScriptId[serverPath];
  }

  /// Initializes [_sourceToModule], [_moduleToSources], and [_sourceToLibrary].
  Future<void> _initializeMapping([
    InvalidatedModuleReport? invalidatedModuleReport,
  ]) async {
    final provider = globalToolConfiguration.loadStrategy.metadataProviderFor(
      _entrypoint,
    );

    final libraryToScripts = await provider.scripts;
    final scriptToModule = await provider.scriptToModule;

    for (final library in libraryToScripts.keys) {
      final scripts = libraryToScripts[library]!;
      final libraryServerPath =
          library.startsWith('dart:')
              ? library
              : DartUri(library, _root).serverPath;

      if (scriptToModule.containsKey(library)) {
        final module = scriptToModule[library]!;

        _sourceToModule[libraryServerPath] = module;
        _moduleToSources.putIfAbsent(module, () => {}).add(libraryServerPath);
        _sourceToLibrary[libraryServerPath] = Uri.parse(library);
        _libraryToModule[library] = module;

        for (final script in scripts) {
          final scriptServerPath =
              script.startsWith('dart:')
                  ? script
                  : DartUri(script, _root).serverPath;

          _sourceToModule[scriptServerPath] = module;
          _moduleToSources[module]!.add(scriptServerPath);
          _sourceToLibrary[scriptServerPath] = Uri.parse(library);
        }
      } else {
        _logger.warning('No module found for library $library');
      }
    }
  }
}
