// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../services/chrome_proxy_service.dart';
import '../utilities/dart_uri.dart';
import 'location.dart';
import 'remote_debugger.dart';

/// The scripts and sourcemaps for the application, both JS and Dart.
class Sources {
  /// Map from Dart server path to tokenPosTable as defined in the
  /// Dart VM Service Protocol:
  /// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
  final _sourceToTokenPosTable = <String, List<List<int>>>{};

  /// Map from Dart server path to all corresponding [Location] data.
  final _sourceToLocation = <String, Set<Location>>{};

  /// Map from JS scriptId to all corresponding [Location] data.
  final _scriptIdToLocation = <String, Set<Location>>{};

  /// Map from JS source url to corresponding Dart server paths.
  final _sourceToServerPaths = <String, Set<String>>{};

  /// Map from JS source url to Chrome script ID.
  final _sourceToScriptId = <String, String>{};

  /// Paths to black box in the Chrome debugger.
  final _pathsToBlackBox = {'/packages/stack_trace/'};

  final AssetHandler _assetHandler;
  final RemoteDebugger _remoteDebugger;

  Sources(this._assetHandler, this._remoteDebugger);

  /// Returns all [Location] data for a provided Dart source.
  Set<Location> locationsForDart(String serverPath) =>
      _sourceToLocation[serverPath] ?? {};

  /// Returns all [Location] data for a provided JS scriptId.
  Set<Location> locationsForJs(String scriptId) =>
      _scriptIdToLocation[scriptId] ?? {};

  /// Called to handle the event that a script has been parsed
  /// and add its sourcemap information.
  Future<Null> scriptParsed(ScriptParsedEvent e) async {
    var script = e.script;
    // TODO(grouma) - This should be configurable.
    await _blackBoxIfNecessary(script);
    var sourceMapContents = await _sourceMap(script);
    if (sourceMapContents == null) return;
    _clearCacheFor(script);
    _sourceToScriptId[script.url] = script.scriptId;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = parse(sourceMapContents);
    if (mapping is SingleMapping) {
      var serverPaths =
          _sourceToServerPaths.putIfAbsent(script.url, () => Set());
      // Create TokenPos for each entry in the source map.
      for (var lineEntry in mapping.lines) {
        for (var entry in lineEntry.entries) {
          var index = entry.sourceUrlId;
          if (index == null) continue;
          var dartUri = DartUri(mapping.urls[index], script.url);
          var location = Location.from(
            script.scriptId,
            lineEntry,
            entry,
            dartUri,
          );
          serverPaths.add(dartUri.serverPath);
          noteLocation(dartUri.serverPath, location, script.scriptId);
        }
      }
    }
  }

  /// Add [location] to our lookups for both the Dart and JS scripts.
  void noteLocation(
      String dartServerPath, Location location, String wipScriptId) {
    _sourceToLocation.putIfAbsent(dartServerPath, () => Set()).add(location);
    _scriptIdToLocation.putIfAbsent(wipScriptId, () => Set()).add(location);
  }

  /// Returns the tokenPosTable for the provided Dart script path as defined
  /// in:
  /// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
  List<List<int>> tokenPosTableFor(String serverPath) {
    var tokenPosTable = _sourceToTokenPosTable[serverPath];
    if (tokenPosTable != null) return tokenPosTable;
    // Construct the tokenPosTable which is of the form:
    // [lineNumber, (tokenId, columnNumber)*]
    tokenPosTable = <List<int>>[];
    var locations = _sourceToLocation[serverPath] ?? {};
    var lineNumberToLocation = <int, Set<Location>>{};
    for (var location in locations) {
      lineNumberToLocation
          .putIfAbsent(location.dartLocation.line, () => Set())
          .add(location);
    }
    for (var lineNumber in lineNumberToLocation.keys) {
      tokenPosTable.add([
        lineNumber,
        for (var location in lineNumberToLocation[lineNumber]) ...[
          location.tokenPos,
          location.dartLocation.column
        ]
      ]);
    }
    _sourceToTokenPosTable[serverPath] = tokenPosTable;
    return tokenPosTable;
  }

  void _clearCacheFor(WipScript script) {
    var serverPaths = _sourceToServerPaths[script.url] ?? {};
    for (var serverPath in serverPaths) {
      _sourceToLocation.remove(serverPath);
      _sourceToTokenPosTable.remove(serverPath);
    }
    // This is the previous script ID for the file with the same URL.
    var scriptId = _sourceToScriptId[script.url];
    _scriptIdToLocation.remove(scriptId);

    _sourceToServerPaths.remove(script.url);
    _sourceToScriptId.remove(script.url);
  }

  /// The source map for a DDC-compiled JS [script].
  Future<String> _sourceMap(WipScript script) {
    var sourceMapUrl = script.sourceMapURL;
    if (sourceMapUrl == null || !sourceMapUrl.endsWith('.ddc.js.map')) {
      return null;
    }
    var scriptPath = DartUri(script.url).serverPath;
    var sourcemapPath = p.url.join(p.url.dirname(scriptPath), sourceMapUrl);
    return _assetHandler(sourcemapPath);
  }

  /// Black boxes the Dart SDK and paths in [_pathsToBlackBox].
  Future<void> _blackBoxIfNecessary(WipScript script) async {
    if (script.url.endsWith('dart_sdk.js')) {
      await _blackBoxSdk(script);
    } else if (_pathsToBlackBox.any((path) => script.url.contains(path))) {
      var lines =
          (await _assetHandler(DartUri(script.url).serverPath)).split('\n');
      await _blackBoxRanges(script.scriptId, [lines.length]);
    }
  }

  /// Black boxes the SDK excluding the range which includes exception logic.
  Future<void> _blackBoxSdk(WipScript script) async {
    var sdkSourceLines =
        (await _assetHandler(DartUri(script.url).serverPath)).split('\n');
    // TODO(grouma) - Find a more robust way to identify this location.
    var throwIndex = sdkSourceLines.indexWhere(
        (line) => line.contains('dart.throw = function throw_(exception) {'));
    if (throwIndex != -1) {
      await _blackBoxRanges(script.scriptId, [throwIndex, throwIndex + 6]);
    }
  }

  Future<void> _blackBoxRanges(String scriptId, List<int> lineNumbers) async {
    await _remoteDebugger.sendCommand('Debugger.setBlackboxedRanges', params: {
      'scriptId': scriptId,
      'positions': [
        {'lineNumber': 0, 'columnNumber': 0},
        for (var line in lineNumbers) {'lineNumber': line, 'columnNumber': 0},
      ]
    });
  }
}
