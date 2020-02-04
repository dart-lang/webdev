// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds/src/debugging/execution_context.dart';
import 'package:path/path.dart' as p;

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
  final _sourceToPackage = <String, String>{};

  // The Chrome script ID to corresponding module.
  final _scriptIdToModule = <String, String>{};

  // The module to corresponding Chrome script ID.
  final _moduleToScriptId = <String, String>{};

  final _moduleExtensionCompleter = Completer<String>();

  Modules(this._remoteDebugger, this._root, this._executionContext);

  /// Completes with the module extension i.e. `.ddc.js` or `.ddk.js`.
  ///
  /// We use the script parsed events from Chrome to determine this information.
  // TODO(grouma) - Do something better here.
  Future<String> get moduleExtension => _moduleExtensionCompleter.future;

  /// Initializes the mapping from source to module.
  ///
  /// Intended to be called multiple times throughout the development workflow,
  /// e.g. after a hot-reload.
  void initialize() {
    // We only clear the source to module mapping as script IDs may persist
    // across hot reloads.
    _sourceToModule.clear();
  }

  /// Returns the module for the Chrome script ID.
  Future<String> moduleForScriptId(String scriptId) async =>
      _scriptIdToModule[scriptId];

  /// Returns the Chrome script ID for the provided module.
  Future<String> scriptIdForModule(String module) async =>
      _moduleToScriptId[module];

  /// Returns the containing module for the provided Dart server path.
  Future<String> moduleForSource(String serverPath) async {
    if (_sourceToModule.isEmpty) {
      await _initializeMapping();
    }
    return _sourceToModule[serverPath];
  }

  /// Returns the containing library importUri for the provided Dart server path.
  Future<String> packageForSource(String serverPath) async {
    if (_sourceToPackage.isEmpty) {
      await _initializeMapping();
    }
    return _sourceToPackage[serverPath];
  }

  /// Checks if the [url] correspond to a module and stores meta data.
  Future<Null> noteModule(String url, String scriptId) async {
    var path = Uri.parse(url).path;
    if (path == null ||
        !(path.endsWith('.ddc.js') || path.endsWith('.ddk.js'))) {
      return;
    }

    // TODO(grouma) - This is wonky. Find a better way.
    if (!_moduleExtensionCompleter.isCompleted) {
      if (path.endsWith('.ddc.js')) {
        _moduleExtensionCompleter.complete('.ddc.js');
      } else {
        _moduleExtensionCompleter.complete('.ddk.js');
      }
    }

    var module =
        // Remove the DDC extension (e.g. .ddc.js) from the path.
        _moduleFor(p.withoutExtension(p.withoutExtension(path)));

    _scriptIdToModule[scriptId] = module;
    _moduleToScriptId[module] = scriptId;
  }

  /// Initializes [_sourceToModule].
  Future<void> _initializeMapping() async {
    var expression = '''
    (function() {
          var dart = $loadModule('dart_sdk').dart;
          var result = {};
          dart.getModuleNames().forEach(function(module){
            Object.keys(dart.getModuleLibraries(module)).forEach(
              function(script){
                result[script] =  '/' + module;
            });
          });
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
      _sourceToModule[serverPath] = _moduleFor(value[dartScript] as String,
          skipRoot: dartScript.startsWith('org-dartlang-app:///'));
      _sourceToPackage[serverPath] = dartScript;
    }
  }

  /// Returns the module for the provided path.
  ///
  /// Module are of the following form:
  ///
  ///   packages/foo/bar/module
  ///   some/root/bar/module
  ///
  String _moduleFor(String path, {bool skipRoot}) {
    skipRoot ??= false;
    var result = '';
    if (path.contains('/packages/')) {
      result = 'packages/${path.split('/packages/').last}';
    } else if (path.contains('/lib/')) {
      var splitModule = path.split('/lib/').first.substring(1).split('/');
      // Special case third_party/dart for Google3.
      if (path.startsWith('/third_party/dart/')) {
        splitModule = splitModule.skip(2).toList();
      }
      result = 'packages/${splitModule.join(".")}/${p.basename(path)}';
    } else if (path.contains('/google3/')) {
      result = path.split('/google3/').last;
    } else if (path.startsWith('/')) {
      path = path.substring(1);
      if (skipRoot) {
        path = path.split('/').skip(1).join('/');
      }
      result = path;
    }
    return result;
  }
}
