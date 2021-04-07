// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'package:async/async.dart';

import '../loaders/strategy.dart';
import '../utilities/dart_uri.dart';

/// Tracks modules for the compiled application.
class Modules {
  final String _root;

  // The Dart server path to containing module.
  final _sourceToModule = <String, String>{};

  // The Dart server path to library import uri
  final _sourceToLibrary = <String, Uri>{};
  var _moduleMemoizer = AsyncMemoizer<void>();

  // The Chrome script ID to corresponding module.
  final _scriptIdToModule = <String, String>{};

  final Map<String, String> _libraryToModule = {};

  String _entrypoint;

  Modules(String root) : _root = root == '' ? '/' : root;

  /// Initializes the mapping from source to module.
  ///
  /// Intended to be called multiple times throughout the development workflow,
  /// e.g. after a hot-reload.
  void initialize(String entrypoint) {
    // We only clear the source to module mapping as script IDs may persist
    // across hot reloads.
    _sourceToModule.clear();
    _sourceToLibrary.clear();
    _libraryToModule.clear();
    _moduleMemoizer = AsyncMemoizer();
    _entrypoint = entrypoint;
  }

  /// Returns the module for the Chrome script ID.
  String moduleForScriptId(String scriptId) => _scriptIdToModule[scriptId];

  /// Returns the containing module for the provided Dart server path.
  Future<String> moduleForSource(String serverPath) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToModule[serverPath];
  }

  /// Returns the containing library importUri for the provided Dart server path.
  Future<Uri> libraryForSource(String serverPath) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToLibrary[serverPath];
  }

  Future<String> moduleForlibrary(String libraryUri) async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _libraryToModule[libraryUri];
  }

  // Returns mapping from server paths to library paths
  Future<Map<String, String>> modules() async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToModule;
  }

  /// Initializes [_sourceToModule] and [_sourceToLibrary].
  Future<void> _initializeMapping() async {
    var provider = globalLoadStrategy.metadataProviderFor(_entrypoint);

    var libraryToScripts = await provider.scripts;
    var scriptToModule = await provider.scriptToModule;

    for (var library in libraryToScripts.keys) {
      var libraryServerPath = library.startsWith('dart:')
          ? library
          : DartUri(library, _root).serverPath;

      _sourceToModule[libraryServerPath] = scriptToModule[library];
      _sourceToLibrary[libraryServerPath] = Uri.parse(library);
      _libraryToModule[library] = scriptToModule[library];

      for (var script in libraryToScripts[library]) {
        var scriptServerPath = script.startsWith('dart:')
            ? script
            : DartUri(script, _root).serverPath;

        _sourceToModule[scriptServerPath] = scriptToModule[library];
        _sourceToLibrary[scriptServerPath] = Uri.parse(library);
      }
    }
  }
}
