// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import '../../asset_handler.dart';
import '../../dwds.dart' show LogWriter;
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

  /// Use `_readAssetOrNull` instead of using this directly, as it handles
  /// logging unsuccessful responses.
  final AssetHandler _assetHandler;

  final LogWriter _logWriter;

  final RemoteDebugger _remoteDebugger;

  final String _root;

  Sources(
      this._assetHandler, this._remoteDebugger, this._logWriter, this._root);

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
    _clearCacheFor(script);
    _sourceToScriptId[script.url] = script.scriptId;
    var sourceMapContents = await _sourceMapOrNull(script);
    if (sourceMapContents == null) return;
    var scriptLocation = p.url.dirname(Uri.parse(script.url).path);
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
          // Source map URLS are relative to the script. They may have platform separators
          // or they may use URL semantics. To be sure, we split and re-join them.
          // This works on Windows because path treats both / and \ as separators.
          // It will fail if the path has both separators in it.
          var relativeSegments = p.split(mapping.urls[index]);
          var path = p.url.joinAll([scriptLocation, ...relativeSegments]);
          var dartUri = DartUri(path, _root);
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

  /// Reads an asset at [path] relative to the server root.
  ///
  /// Returns `null` and logs the response if the status is anything other than
  /// [HttpStatus.ok].
  Future<String> _readAssetOrNull(String path) async {
    var response = await _assetHandler.getRelativeAsset(path);
    var responseText = '';
    var hasError = false;
    try {
      responseText = await response.readAsString();
    } on ClientException {
      hasError = true;
      responseText = '<response not available>';
    }
    if (response.statusCode == HttpStatus.ok && !hasError) {
      return responseText;
    } else {
      _logWriter(Level.WARNING, '''
Failed to load asset at path: $path.

Status code: ${response.statusCode}

Headers:
${const JsonEncoder.withIndent('  ').convert(response.headers)}

Content:
$responseText}
''');
      return null;
    }
  }

  /// The source map for a DDC-compiled JS [script].
  ///
  /// Returns `null` and logs if it can't be read.
  Future<String> _sourceMapOrNull(WipScript script) {
    var sourceMapUrl = script.sourceMapURL;
    if (sourceMapUrl == null ||
        !(sourceMapUrl.endsWith('.ddc.js.map') ||
            sourceMapUrl.endsWith('.ddk.js.map'))) {
      return null;
    }
    var scriptPath = DartUri(script.url).serverPath;
    var sourcemapPath = p.url.join(p.url.dirname(scriptPath), sourceMapUrl);
    return _readAssetOrNull(sourcemapPath);
  }

  /// Black boxes the Dart SDK and paths in [_pathsToBlackBox].
  Future<void> _blackBoxIfNecessary(WipScript script) async {
    if (script.url.endsWith('dart_sdk.js')) {
      await _blackBoxSdk(script);
    } else if (_pathsToBlackBox.any((path) => script.url.contains(path))) {
      var content = await _readAssetOrNull(DartUri(script.url).serverPath);
      if (content == null) return;
      var lines = content.split('\n');
      await _blackBoxRanges(script.scriptId, [lines.length]);
    }
  }

  /// Black boxes the SDK excluding the range which includes exception logic.
  Future<void> _blackBoxSdk(WipScript script) async {
    var content = await _readAssetOrNull(DartUri(script.url).serverPath);
    if (content == null) return;
    var sdkSourceLines = content.split('\n');
    // TODO(grouma) - Find a more robust way to identify this location.
    var throwIndex = sdkSourceLines.indexWhere(
        (line) => line.contains('dart.throw = function throw_(exception) {'));
    if (throwIndex != -1) {
      await _blackBoxRanges(script.scriptId, [throwIndex, throwIndex + 6]);
    }
  }

  Future<void> _blackBoxRanges(String scriptId, List<int> lineNumbers) async {
    try {
      await _remoteDebugger
          .sendCommand('Debugger.setBlackboxedRanges', params: {
        'scriptId': scriptId,
        'positions': [
          {'lineNumber': 0, 'columnNumber': 0},
          for (var line in lineNumbers) {'lineNumber': line, 'columnNumber': 0},
        ]
      });
    } catch (_) {
      // Attempting to set ranges immediately after a refresh can cause issues
      // as the corresponding script will no longer exist. Silently ignore
      // these failures.
    }
  }
}
