// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';

import '../debugging/execution_context.dart';
import '../loaders/strategy.dart';
import '../utilities/dart_uri.dart';
import '../utilities/shared.dart';
import 'remote_debugger.dart';

/// Contains meta data and helpful methods for DDC modules.
class Modules {
  final String _root;
  final RemoteDebugger _remoteDebugger;
  final ExecutionContext _executionContext;
  // The Dart server path to containing module.
  final _sourceToModule = <String, String>{};
  // The Dart server path to library import uri
  final _sourceToLibrary = <String, Uri>{};
  var _moduleMemoizer = AsyncMemoizer<void>();

  // The Chrome script ID to corresponding module.
  final _scriptIdToModule = <String, String>{};

  // The module to corresponding Chrome script ID.
  final _moduleToScriptId = <String, String>{};

  Modules(
    this._remoteDebugger,
    String root,
    this._executionContext,
  ) : _root = root == '' ? '/' : root;

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
  Future<String> moduleForScriptId(String scriptId) async =>
      _scriptIdToModule[scriptId];

  /// Returns the Chrome script ID for the provided module.
  Future<String> scriptIdForModule(String module) async =>
      _moduleToScriptId[module];

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
    // TODO(grouma) - We should talk to the compiler directly to greatly
    // improve the performance here.
    var expression = '''
(function() {
  var dart = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk').dart;
  var result = {};
  for (module of dart.getModuleNames()) {
    for (script of Object.keys(dart.getModuleLibraries(module))) {
      result[script] = module;
    }
  }
  return result;
})();
      ''';
    var response =
        await _remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'returnByValue': true,
      'contextId': await _executionContext.id,
    });
    handleErrorIfPresent(response);
    var value = response.result['result']['value'] as Map<String, dynamic>;
    for (var dartScript in value.keys) {
      if (!dartScript.endsWith('.dart')) continue;
      var serverPath = DartUri(dartScript, _root).serverPath;
      _sourceToModule[serverPath] = value[dartScript] as String;
      _sourceToLibrary[serverPath] = Uri.parse(dartScript);
    }
  }
}
