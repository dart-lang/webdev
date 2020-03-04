// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:dwds/src/debugging/execution_context.dart';
import 'package:path/path.dart' as p;

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
  final _moduleCompleter = Completer<bool>();

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
    _sourceToLibrary.clear();
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
    await _moduleCompleter.future;
    return _sourceToModule[serverPath];
  }

  /// Returns the containing library importUri for the provided Dart server path.
  Future<Uri> libraryForSource(String serverPath) async {
    await _moduleCompleter.future;
    return _sourceToLibrary[serverPath];
  }

  // Returns mapping from server paths to library paths
  Future<Map<String, String>> modules() async {
    await _moduleCompleter.future;
    return _sourceToModule;
  }

  /// Checks if the [url] correspond to a module and stores meta data.
  Future<Null> noteModule(String url, String scriptId) async {
    var path = Uri.parse(url).path;
    if (path == null ||
        !(path.endsWith('.ddc.js') ||
            path.endsWith('.ddk.js') ||
            path.endsWith('.lib.js'))) {
      return;
    }

    // TODO(grouma) - This is wonky. Find a better way.
    if (!_moduleExtensionCompleter.isCompleted) {
      if (path.endsWith('.ddc.js')) {
        _moduleExtensionCompleter.complete('.ddc.js');
      } else if (path.endsWith('.ddk.js')) {
        _moduleExtensionCompleter.complete('.ddk.js');
      } else {
        _moduleExtensionCompleter.complete('.lib.js');
      }
    }

    var serverPath = _jsModulePathToServerPath(path);
    var module = await moduleForSource(serverPath);

    _scriptIdToModule[scriptId] = module;
    _moduleToScriptId[module] = scriptId;
  }

  String _jsModulePathToServerPath(String path) {
    // remove extensions, such as '.ddc.js'
    var serverPath = p.withoutExtension(p.withoutExtension(path));
    // server path does not contain leading '/'
    serverPath =
        serverPath.startsWith('/') ? serverPath.substring(1) : serverPath;
    // server path has '.dart' extension
    serverPath = serverPath.endsWith('.dart') ? serverPath : '$serverPath.dart';
    // server path should be relative to the asset server root
    serverPath = adjustForRoot(serverPath);
    return DartUri('/$serverPath', _root).serverPath;
  }

  /// Make path relative to the asset server's serving root.
  ///
  /// Remove the asset server root directory for non-package files, if any,
  /// but do not remove the _root, which is the directory off the
  /// asset server root. This is needed to produce paths that will be used
  /// in requests to the asset server, such as dart script paths, dart
  /// locations, or source map paths. Asset server is serving from the asset
  /// server root directory, so it expects the requests to be relative to it.
  // Note: This is a temporary workaround until we solve inconsistencies in
  // different configurations by introducing module name and path translation
  // interfaces between compiler, asset server, and the debugger.
  // TODO(annagrin): module interface
  // [issue #910](https://github.com/dart-lang/webdev/issues/910)
  String adjustForRoot(String path) {
    // path == 'dir/main.dart' => pathRoot == 'dir'
    // path == 'main.dart' => pathRoot == '.'
    var segments = p.split(path);
    var pathRoot = p.split(p.dirname(path))[0];

    // _root == 'http:/localhost:port/dir/index.html' => indexRoot == 'dir'
    // _root == 'http:/localhost:port/index.html' => indexRoot == '.'
    var indexPath = Uri.parse(_root).path.substring(1);
    var indexRoot = p.split(p.dirname(indexPath))[0];

    // remove the root from path only if not equal to packages or indexRoot
    var result = pathRoot == 'packages' || pathRoot == indexRoot
        ? path
        : p.joinAll(segments.skip(1));
    return result;
  }

  /// Initializes [_sourceToModule].
  Future<void> _initializeMapping() async {
    if (_moduleCompleter.isCompleted) return;
    var expression = '''
    (function() {
          var dart = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk').dart;
          var result = {};
          dart.getModuleNames().forEach(function(module){
            Object.keys(dart.getModuleLibraries(module)).forEach(
              function(script){
                result[script] = module;
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

      // get module name from module Uri
      // Note: This is a temporary workaround until we solve inconsistencies
      // in different configurations by introducing module name and path
      // translation interfaces between compiler, asset server, and the
      // debugger.
      // TODO(annagrin): module interface
      // [issue #910](https://github.com/dart-lang/webdev/issues/910)
      var moduleUri = Uri.parse(value[dartScript] as String);
      var module = _moduleFor(moduleUri.path);
      _sourceToModule[serverPath] = module;
      _sourceToLibrary[serverPath] = Uri.parse(dartScript);
    }
    _moduleCompleter.complete();
  }

  /// Returns the module for the provided path.
  ///
  /// Module are of the following form:
  ///
  ///   packages/foo/bar/module
  ///   some/root/bar/module
  ///
  String _moduleFor(String path, {bool skipRoot}) {
    path = '/$path';
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
