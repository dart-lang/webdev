// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';

import '../loaders/strategy.dart';
import '../utilities/dart_uri.dart';
import 'metadata/provider.dart';

/// Tracks modules for the compiled application.
class Modules {
  final String _root;
  final MetadataProvider _metadataProvider;

  // The Dart server path to containing module.
  final _sourceToModule = <String, String>{};

  // The Dart server path to library import uri
  final _sourceToLibrary = <String, Uri>{};
  var _moduleMemoizer = AsyncMemoizer<void>();

  // The Chrome script ID to corresponding module.
  final _scriptIdToModule = <String, String>{};

  // The module to corresponding Chrome script ID.
  final _moduleToScriptId = <String, String>{};

  Modules(this._metadataProvider, String root)
      : _root = root == '' ? '/' : root;

  /// Initializes the mapping from source to module.
  ///
  /// Intended to be called multiple times throughout the development workflow,
  /// e.g. after a hot-reload.
  void initialize() {
    // We only clear the source to module mapping as script IDs may persist
    // across hot reloads.
    _sourceToModule.clear();
    _sourceToLibrary.clear();
    _moduleMemoizer = AsyncMemoizer();
  }

  /// Returns the module for the Chrome script ID.
  String moduleForScriptId(String scriptId) => _scriptIdToModule[scriptId];

  /// Returns the Chrome script ID for the provided module.
  String scriptIdForModule(String module) => _moduleToScriptId[module];

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

  /// Checks if the [url] correspond to a module and stores meta data.
  Future<Null> noteModule(String url, String scriptId) async {
    var path = Uri.parse(url).path;
    if (path == null) return;
    var module = globalLoadStrategy.moduleForServerPath(path);
    if (module == null) return;
    _scriptIdToModule[scriptId] = module;
    _moduleToScriptId[module] = scriptId;
  }

  /// Initializes [_sourceToModule] and [_sourceToLibrary].
  Future<void> _initializeMapping() async {
    var scriptToModule = await _metadataProvider.scriptToModule;
    for (var script in scriptToModule.keys) {
      var serverPath = DartUri(script, _root).serverPath;
      _sourceToModule[serverPath] = scriptToModule[script];
      _sourceToLibrary[serverPath] = Uri.parse(script);
    }
  }
}
