// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:source_maps/parser.dart';
import 'package:source_maps/source_maps.dart';

import '../services/chrome_proxy_service.dart';
import '../utilities/dart_uri.dart';
import 'location.dart';
import 'remote_debugger.dart';
import 'sources.dart';

/// Contains meta data and helpful methods for DDC modules.
class ModuleMetaData {
  final Sources _sources;
  final String _root;
  final RemoteDebugger _remoteDebugger;
  final _sourceToModule = <String, String>{};
  final _scriptIdToModule = <String, String>{};
  final _moduleToScriptId = <String, String>{};
  final _moduleToLocations = <String, Set<Location>>{};
  final _moduleExtensionCompleter = Completer<String>();

  var _initializedCompleter = Completer();

  ModuleMetaData(this._sources, this._remoteDebugger, this._root);

  /// Completes with the module extension i.e. `.ddc.js` or `.ddk.js`.
  ///
  /// We use the script parsed events from Chrome to determine this information.
  // TODO(grouma) - Do something better here.
  Future<String> get _moduleExtension => _moduleExtensionCompleter.future;

  Future<String> moduleForScriptId(String scriptId) async =>
      _scriptIdToModule[scriptId];

  /// Returns the containing module for the provided Dart server path.
  Future<String> moduleForSource(String serverPath) async {
    await _initializedCompleter.future;
    return _sourceToModule[serverPath];
  }

  /// Initializes the mapping from source to module.
  ///
  /// Intended to be called multiple times throughout the development workflow,
  /// e.g. after a hot-reload.
  void initializeMapping() {
    _initializedCompleter = Completer();
    _initialize();
  }

  /// Handles a script parsed event within Chrome.
  Future<Null> noteScript(String url, String scriptId) async {
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

    var module = p
        .withoutExtension(p.withoutExtension(Uri.parse(url).path))
        .substring(1);

    _scriptIdToModule[scriptId] = module;
    _moduleToScriptId[module] = scriptId;
  }

  Future<void> _initialize() async {
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
      // TODO(comment);
      if (scriptUri.scheme == 'org-dartlang-app') {
        moduleUri = moduleUri.replace(scheme: 'org-dartlang-app');
      } else if (scriptUri.scheme == 'package') {
        moduleUri = moduleUri.replace(
            scheme: 'package', path: moduleUri.path.split('/packages/').last);
      }
      _sourceToModule[DartUri(dartScript, _root).serverPath] =
          DartUri(moduleUri.toString()).serverPath;
    }
    _initializedCompleter.complete();
  }

  Future<Set<Location>> locationsForModule(String module) async {
    if (_moduleToLocations[module] != null) return _moduleToLocations[module];
    var result = <Location>{};
    if (module?.isEmpty ?? true) return result;
    var moduleExtension = await _moduleExtension;
    var modulePath = '$module$moduleExtension';
    var sourceMapContents = await _sources.readAssetOrNull('$modulePath.map');
    var scriptLocation = p.url.dirname('/$modulePath');
    if (sourceMapContents == null) return result;
    var scriptId = _moduleToScriptId[module];
    if (scriptId == null) return result;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = parse(sourceMapContents);
    if (mapping is SingleMapping) {
      // Create TokenPos for each entry in the source map.
      for (var lineEntry in mapping.lines) {
        for (var entry in lineEntry.entries) {
          var index = entry.sourceUrlId;
          if (index == null) continue;
          // Source map URLS are relative to the script. They may have platform separators
          // or they may use URL semantics. To be sure, we split and re-join them.
          // This works on Windows because path treats both / and \ as separators.
          // It will fail if the path has both separators in it.
          var relativeSegments = p.split(mapping.urls[index]);
          var path = p.url.joinAll([scriptLocation, ...relativeSegments]);
          var dartUri = DartUri(path, _root);
          result.add(Location.from(
            scriptId,
            lineEntry,
            entry,
            dartUri,
          ));
        }
      }
    }
    _moduleToLocations[module] = result;
    return result;
  }
}
