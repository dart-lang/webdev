// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;

import '../services/chrome_proxy_service.dart';
import '../utilities/dart_uri.dart';
import 'remote_debugger.dart';

/// Contains meta data and helpful methods for DDC modules.
class Modules {
  final String _root;
  final RemoteDebugger _remoteDebugger;
  // The Dart server path to containing module.
  final _sourceToModule = <String, String>{};

  // The Chrome script ID to corresponding module.
  final _scriptIdToModule = <String, String>{};

  // The module to corresponding Chrome script ID.
  final _moduleToScriptId = <String, String>{};

  final _moduleExtensionCompleter = Completer<String>();

  var _initializedCompleter = Completer();

  Modules(this._remoteDebugger, this._root);

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
    _initializedCompleter = Completer();
    _initializeMapping();
  }

  /// Returns the module for the Chrome script ID.
  Future<String> moduleForScriptId(String scriptId) async =>
      _scriptIdToModule[scriptId];

  /// Returns the Chrome script ID for the provided module.
  Future<String> scriptIdForModule(String module) async =>
      _moduleToScriptId[module];

  /// Returns the containing module for the provided Dart server path.
  Future<String> moduleForSource(String serverPath) async {
    await _initializedCompleter.future;
    return _sourceToModule[serverPath];
  }

  /// Checks if the [url] correspond to a module and stores meta data.
  Future<Null> noteModule(String url, String scriptId) async {
    if (url == null || !(url.endsWith('.ddc.js') || url.endsWith('.ddk.js'))) {
      return;
    }

    // TODO(grouma) - This is wonky. Find a better way.
    if (!_moduleExtensionCompleter.isCompleted) {
      if (url.endsWith('.ddc.js')) {
        _moduleExtensionCompleter.complete('.ddc.js');
      } else {
        _moduleExtensionCompleter.complete('.ddk.js');
      }
    }

    // Remove the DDC extension (e.g. .ddc.js) from the path.
    var module = p
        .withoutExtension(p.withoutExtension(Uri.parse(url).path))
        .substring(1);

    _scriptIdToModule[scriptId] = module;
    _moduleToScriptId[module] = scriptId;
  }

  /// Initializes [_sourceToModule].
  Future<void> _initializeMapping() async {
    var expression = '''
    (function() {
          var dart = require('dart_sdk').dart;
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
    var response = await _remoteDebugger.sendCommand('Runtime.evaluate',
        params: {'expression': expression, 'returnByValue': true});
    handleErrorIfPresent(response);
    var value = response.result['result']['value'] as Map<String, dynamic>;
    for (var dartScript in value.keys) {
      if (!dartScript.endsWith('.dart')) continue;
      var scriptUri = Uri.parse(dartScript);
      var moduleUri = Uri.parse(value[dartScript] as String);
      // The module uris returned by the expression contain the root. Rewrite
      // the uris so that DartUri properly accounts for this fact.
      if (scriptUri.scheme == 'org-dartlang-app') {
        moduleUri = moduleUri.replace(scheme: 'org-dartlang-app');
      } else if (scriptUri.scheme == 'package') {
        moduleUri = moduleUri.replace(
            scheme: 'package', path: moduleUri.path.split('/packages/').last);
      }
      // TODO(grouma) - handle G3 scheme.
      _sourceToModule[DartUri(dartScript, _root).serverPath] =
          DartUri(moduleUri.toString()).serverPath;
    }
    _initializedCompleter.complete();
  }
}
