// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:source_maps/source_maps.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'chrome_proxy_service.dart';
import 'dart_uri.dart';
import 'location.dart';

/// The scripts and sourcemaps for the application, both JS and Dart.
class Sources {
  /// Controller for a stream of events when a source map is loaded.
  final _sourceMapLoadedController = StreamController<String>.broadcast();

  /// Map from Dart server path to tokenPosTable as defined in the
  /// Dart VM Service Protocol:
  /// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
  final _sourceToTokenPosTable = <String, List<List<int>>>{};

  /// Map from Dart server path to all corresponding [Location] data.
  final _sourceToLocation = <String, Set<Location>>{};

  /// Map from JS scriptId to all corresponding [Location] data.
  final _scriptIdToLocation = <String, Set<Location>>{};

  final AssetHandler _assetHandler;

  Sources(this._assetHandler);

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
    var sourceMapContents = await _sourceMap(script);
    if (sourceMapContents == null) return;
    // This happens to be a [SingleMapping] today in DDC.
    var mapping = parse(sourceMapContents);
    if (mapping is SingleMapping) {
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
          _sourceToLocation
              .putIfAbsent(dartUri.serverPath, () => Set())
              .add(location);
          _scriptIdToLocation
              .putIfAbsent(script.scriptId, () => Set())
              .add(location);
        }
      }

      // Notify which Dart file's source maps have been parsed.
      for (var serverPath in _sourceToLocation.keys) {
        _sourceMapLoadedController.add(serverPath);
      }
    }
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

  /// The source map for a DDC-compiled JS [script].
  // TODO(grouma) - Reuse this logic in `DartUri`.
  Future<String> _sourceMap(WipScript script) {
    var sourceMapUrl = script.sourceMapURL;
    if (sourceMapUrl == null || !sourceMapUrl.endsWith('.ddc.js.map')) {
      return null;
    }
    var scriptPath = DartUri(script.url).serverPath;
    var sourcemapPath = p.join(p.dirname(scriptPath), sourceMapUrl);
    return _assetHandler(sourcemapPath);
  }
}
