// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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

  // Returns mapping from server paths to library paths
  Future<Map<String, String>> modules() async {
    await _moduleMemoizer.runOnce(_initializeMapping);
    return _sourceToModule;
  }

  /// Initializes [_sourceToModule] and [_sourceToLibrary].
  Future<void> _initializeMapping() async {
    var scriptToModule = await globalLoadStrategy
        .metadataProviderFor(_entrypoint)
        .scriptToModule;
    for (var script in scriptToModule.keys) {
      var serverPath = DartUri(script, _root).serverPath;
      _sourceToModule[serverPath] = scriptToModule[script];
      _sourceToLibrary[serverPath] = Uri.parse(script);
    }
  }
}
