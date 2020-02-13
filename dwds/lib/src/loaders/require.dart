// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:shelf/shelf.dart';

import 'strategy.dart';

/// JavaScript snippet to determine the base URL of the current path.
const _baseUrlScript = '''
var baseUrl = (function () {
  // Attempt to detect --precompiled mode for tests, and set the base url
  // appropriately, otherwise set it to '/'.
  var pathParts = location.pathname.split("/");
  if (pathParts[0] == "") {
    pathParts.shift();
  }
  if (pathParts.length > 1 && pathParts[1] == "test") {
    return "/" + pathParts.slice(0, 2).join("/") + "/";
  }
  // Attempt to detect base url using <base href> html tag
  // base href should start and end with "/"
  if (typeof document !== 'undefined') {
    var el = document.getElementsByTagName('base');
    if (el && el[0] && el[0].getAttribute("href") && el[0].getAttribute
    ("href").startsWith("/") && el[0].getAttribute("href").endsWith("/")){
      return el[0].getAttribute("href");
    }
  }
  // return default value
  return "/";
}());
''';

/// JavaScript snippet to determine the directory a script was run from.
const _currentDirectoryScript = r'''
var _currentDirectory = (function () {
  var _url;
  var lines = new Error().stack.split('\n');
  function lookupUrl() {
    if (lines.length > 2) {
      var match = lines[1].match(/^\s+at (.+):\d+:\d+$/);
      // Chrome.
      if (match) return match[1];
      // Chrome nested eval case.
      match = lines[1].match(/^\s+at eval [(](.+):\d+:\d+[)]$/);
      if (match) return match[1];
      // Edge.
      match = lines[1].match(/^\s+at.+\((.+):\d+:\d+\)$/);
      if (match) return match[1];
      // Firefox.
      match = lines[0].match(/[<][@](.+):\d+:\d+$/)
      if (match) return match[1];
    }
    // Safari.
    return lines[0].match(/(.+):\d+:\d+$/)[1];
  }
  _url = lookupUrl();
  var lastSlash = _url.lastIndexOf('/');
  if (lastSlash == -1) return _url;
  var currentDirectory = _url.substring(0, lastSlash + 1);
  return currentDirectory;
})();
''';

/// A load strategy for the require-js module system.
class RequireStrategy extends LoadStrategy {
  @override
  final ReloadConfiguration reloadConfiguration;

  /// The module extension, e.g. `.ddc`.
  final String _moduleExtension;

  final String _requireDigestsPath = r'$requireDigestsPath';

  /// Returns a map of module name to corresponding module path for the provided
  /// Dart application entrypoint.
  ///
  /// For example:
  ///
  ///   web/main -> main.ddc
  ///   packages/path/path -> packages/path/path.ddc
  ///
  final Future<Map<String, String>> Function(String entrypoint) _moduleProvider;

  /// Returns a map of module name to corresponding digest value.
  ///
  /// For example:
  ///
  ///   web/main.ddc.js -> 8363b363f74b41cac955024ab8b94a3f
  ///   packages/path/path.ddc.js -> d348c2a4647e998011fe305f74f22961
  ///
  final Future<Map<String, String>> Function(String entrypoint)
      _digestsProvider;

  RequireStrategy(
    this.reloadConfiguration,
    this._moduleExtension,
    this._moduleProvider,
    this._digestsProvider,
  );

  @override
  Handler get handler => (request) async {
        if (request.url.path.endsWith(_requireDigestsPath)) {
          var digests =
              await _digestsProvider(request.url.queryParameters['entrypoint']);
          return Response.ok(json.encode(digests));
        }
        return null;
      };

  @override
  String get id => 'require-js';

  @override
  String get loadLibrariesSnippet =>
      'let libs = $loadModuleSnippet("dart_sdk").dart.getLibraries();\n';

  @override
  String get loadModuleSnippet => 'require';

  /// Require JS config for ddc.
  ///
  /// Sets the base url to `/` so that all modules can be loaded using absolute
  /// paths which simplifies a lot of scenarios.
  ///
  /// Sets the timeout for loading modules to infinity (0).
  ///
  /// Sets up the custom module paths.
  ///
  /// Adds error handler code for require.js which requests a `.errors` file for
  /// any failed module, and logs it to the console.
  String get _requireJsConfig => '''
$_baseUrlScript;
require.config({
    baseUrl: baseUrl,
    waitSeconds: 0,
    paths: customModulePaths
});
const modulesGraph = new Map();
function getRegisteredModuleName(moduleMap) {
  if (\$requireLoader.moduleIdToUrl.has(moduleMap.name + '$_moduleExtension')) {
    return moduleMap.name + '$_moduleExtension';
  }
  return moduleMap.name;
}
requirejs.onResourceLoad = function (context, map, depArray) {
  const name = getRegisteredModuleName(map);
  const depNameArray = depArray.map(getRegisteredModuleName);
  if (modulesGraph.has(name)) {
    var previousDeps = modulesGraph.get(name);
    var changed = previousDeps.length != depNameArray.length;
    changed = changed || depNameArray.some(function(depName) {
      return !previousDeps.includes(depName);
    });
    if (changed) {
      console.warn("Dependencies graph change for module '" + name + "' detected. " +
        "Dependencies was [" + previousDeps + "], now [" +  depNameArray.map((depName) => depName) +"]. " +
        "Page can't be hot-reloaded, firing full page reload.");
      window.location.reload();
    }
  } else {
    modulesGraph.set(name, []);
    for (const depName of depNameArray) {
      if (!\$requireLoader.moduleParentsGraph.has(depName)) {
        \$requireLoader.moduleParentsGraph.set(depName, []);
      }
      \$requireLoader.moduleParentsGraph.get(depName).push(name);
      modulesGraph.get(name).push(depName);
    }
  }
};
''';

  @override
  Future<String> bootstrapFor(String entrypoint) async =>
      await _requireLoaderSetup(entrypoint) + _requireJsConfig;

  @override
  String loadClientSnippet(String clientScript) =>
      'window.\$requireLoader.forceLoadModule("$clientScript");\n';

  Future<String> _requireLoaderSetup(String entrypoint) async {
    var modulePaths = await _moduleProvider(entrypoint);
    return '''
$_currentDirectoryScript
$_baseUrlScript
let modulePaths = ${const JsonEncoder.withIndent(" ").convert(modulePaths)};
if(!window.\$requireLoader) {
   window.\$requireLoader = {
     digestsPath: '$_requireDigestsPath?entrypoint=$entrypoint',
     moduleIdToUrl: new Map(),
     urlToModuleId: new Map(),
     rootDirectories: new Array(),
     // Used in package:build_runner/src/server/build_updates_client/hot_reload_client.dart
     moduleParentsGraph: new Map(),
     moduleLoadingErrorCallbacks: new Map(),
     forceLoadModule: function (moduleName, callback, onError) {
       if (moduleName.endsWith('$_moduleExtension')) {
         moduleName = moduleName.substring(0, moduleName.length - ${_moduleExtension.length});
       }
       if (typeof onError != 'undefined') {
         var errorCallbacks = \$requireLoader.moduleLoadingErrorCallbacks;
         if (!errorCallbacks.has(moduleName)) {
           errorCallbacks.set(moduleName, new Set());
         }
         errorCallbacks.get(moduleName).add(onError);
       }
       requirejs.undef(moduleName);
       requirejs([moduleName], function() {
         if (typeof onError != 'undefined') {
           errorCallbacks.get(moduleName).delete(onError);
         }
         if (typeof callback != 'undefined') {
           callback();
         }
       });
     },
     getModuleLibraries: null, // set up by _initializeTools
   };
}
let customModulePaths = {};
window.\$requireLoader.rootDirectories.push(window.location.origin + baseUrl);
for (let moduleName of Object.getOwnPropertyNames(modulePaths)) {
  let modulePath = modulePaths[moduleName];
  if (modulePath != moduleName) {
    customModulePaths[moduleName] = modulePath;
  }
  var src = window.location.origin + '/' + modulePath + '.js';
  if (window.\$requireLoader.moduleIdToUrl.has(moduleName)) {
    continue;
  }
  \$requireLoader.moduleIdToUrl.set(moduleName, src);
  \$requireLoader.urlToModuleId.set(src, moduleName);
}
''';
  }
}
