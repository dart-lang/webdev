// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.import 'dart:async';

import 'dart:convert';

import '../../../dwds.dart';
import '../../debugging/execution_context.dart';
import '../../debugging/remote_debugger.dart';
import '../../loaders/strategy.dart';
import '../../utilities/shared.dart';

/// Provider of DDC meta data for a compiled application.
abstract class MetadataProvider {
  /// A list of all libraries in the Dart application.
  ///
  /// Example:
  ///
  ///  [
  ///     dart:web_gl,
  ///     dart:math,
  ///     org-dartlang-app:///web/main.dart
  ///  ]
  ///
  Future<List<String>> get libraries;

  /// A map of script to corresponding parts.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///     [
  ///       org-dartlang-app:///web/a.part.dart,
  ///       org-dartlang-app:///web/b.part.dart,
  ///     ]
  ///  }
  ///
  Future<Map<String, List<String>>> get scripts;

  /// A map of script to containing module.
  ///
  /// Example:
  ///
  /// {
  ///   org-dartlang-app:///web/main.dart :
  ///   web/main
  /// }
  ///
  Future<Map<String, String>> get scriptToModule;

  /// Initializes the provider for the given Dart application entrypoint.
  Future<void> initialize(String entrypointPath);
}

/// A provider of meta data in which data is collected from the running
/// application in Chrome.
class ChromeMetadataProvider implements MetadataProvider {
  final RemoteDebugger _remoteDebugger;
  final ExecutionContext _executionContext;

  ChromeMetadataProvider(this._remoteDebugger, this._executionContext);

  @override
  Future<List<String>> get libraries async {
    var expression = '''
      (function() {
        ${globalLoadStrategy.loadLibrariesSnippet}
        return libs;
      })()
     ''';
    var result = await _remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'returnByValue': true,
      'contextId': await _executionContext.id,
    });
    handleErrorIfPresent(result, evalContents: expression);
    var libraries = List<String>.from(result.result['result']['value'] as List);
    // Filter out any non-Dart libraries, which basically means the .bootstrap
    // library from build_web_runners.
    return libraries
        .where((name) => name.startsWith('dart:') || name.endsWith('.dart'))
        .toList();
  }

  @override
  Future<Map<String, String>> get scriptToModule async {
    var result = <String, String>{};
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
      result[dartScript] = value[dartScript] as String;
    }
    return result;
  }

  @override
  Future<Map<String, List<String>>> get scripts async {
    var libraryUris = await libraries;
    // We can't pass parameters to an eval, so encode the list and inline it in
    // the expression.
    var listAsJson = jsonEncode(libraryUris);
    var expression = '''
    (function() {
      var uris = JSON.parse('$listAsJson');
      var allScripts = {};
      var sdkUtils = ${globalLoadStrategy.loadModuleSnippet}('dart_sdk').dart;
      for (var uri of uris) {
        var parts = sdkUtils.getParts(uri);
        allScripts[uri] = parts;
      }
      return allScripts;
    })()
    ''';
    var result = await _remoteDebugger.sendCommand('Runtime.evaluate', params: {
      'expression': expression,
      'returnByValue': true,
      'contextId': await _executionContext.id,
    });
    handleErrorIfPresent(result, evalContents: expression);
    var allScripts = result.result['result']['value'] as Map<String, dynamic>;
    var scripts = <String, List<String>>{};
    for (var script in allScripts.keys) {
      scripts[script] = (allScripts[script] as List).cast<String>();
    }
    return scripts;
  }

  @override
  Future<void> initialize(String entrypointPath) async {
    // This is a no-op as the necessary information is already contained in the
    // running Dart application.
  }
}

/// A provider of metadata in which data is collected through DDC outputs.
class FileMetadataProvider implements MetadataProvider {
  final AssetReader _assetReader;

  FileMetadataProvider(this._assetReader);

  @override
  Future<List<String>> get libraries => throw UnimplementedError();

  @override
  Future<Map<String, String>> get scriptToModule => throw UnimplementedError();

  @override
  Future<Map<String, List<String>>> get scripts => throw UnimplementedError();

  @override
  Future<void> initialize(String entrypointPath) async {
    // The merged metadata resides next to the entrypoint.
    var serverPath =
        entrypointPath.replaceAll('.app.bootstrap.js', '.merged_metadata');
    var contents = await _assetReader.metadataContents(serverPath);
    print(contents);
    // TODO(grouma) - parse the contents.
    throw UnimplementedError();
  }
}
