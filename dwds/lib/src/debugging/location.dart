// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:source_maps/parser.dart';
import 'package:source_maps/source_maps.dart';

import '../utilities/dart_uri.dart';
import 'modules.dart';

var _startTokenId = 1337;

/// A source location, with both Dart and JS information.
class Location {
  final JsLocation jsLocation;

  final DartLocation dartLocation;

  /// An arbitrary integer value used to represent this location.
  final int tokenPos;

  Location._(
    this.jsLocation,
    this.dartLocation,
  ) : tokenPos = _startTokenId++;

  static Location from(
    String scriptId,
    TargetLineEntry lineEntry,
    TargetEntry entry,
    DartUri dartUri,
  ) {
    var dartLine = entry.sourceLine;
    var dartColumn = entry.sourceColumn;
    var jsLine = lineEntry.line;
    var jsColumn = entry.column;
    // lineEntry data is 0 based according to:
    // https://docs.google.com/document/d/1U1RGAehQwRypUTovF1KRlpiOFze0b-_2gc6fAH0KY0k
    return Location._(JsLocation.fromZeroBased(scriptId, jsLine, jsColumn),
        DartLocation.fromZeroBased(dartUri, dartLine, dartColumn));
  }
}

/// Location information for a Dart source.
class DartLocation {
  final DartUri uri;

  /// 1 based row offset within the Dart source code.
  final int line;

  /// 1 based column offset within the Dart source code.
  final int column;

  DartLocation._(
    this.uri,
    this.line,
    this.column,
  );

  static DartLocation fromZeroBased(DartUri uri, int line, int column) =>
      DartLocation._(uri, line + 1, column + 1);

  static DartLocation fromOneBased(DartUri uri, int line, int column) =>
      DartLocation._(uri, line, column);
}

/// Location information for a JS source.
class JsLocation {
  /// The script ID as provided by Chrome.
  final String scriptId;

  /// 1 based row offset within the JS source code.
  final int line;

  /// 1 based column offset within the JS source code.
  final int column;

  JsLocation._(
    this.scriptId,
    this.line,
    this.column,
  );

  static JsLocation fromZeroBased(String scriptId, int line, int column) =>
      JsLocation._(scriptId, line + 1, column + 1);

  static JsLocation fromOneBased(String scriptId, int line, int column) =>
      JsLocation._(scriptId, line, column);
}

class LocationMetaData {
  /// Map from Dart server path to all corresponding [Location] data.
  final _sourceToLocation = <String, Set<Location>>{};

  /// Map from JS scriptId to all corresponding [Location] data.
  final _scriptIdToLocation = <String, Set<Location>>{};

  /// Map from Dart server path to tokenPosTable as defined in the
  /// Dart VM Service Protocol:
  /// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
  final _sourceToTokenPosTable = <String, List<List<int>>>{};

  /// Set of all modules for which the corresponding source map has been
  /// processed.
  final _processedModules = <String>{};

  final ModuleMetaData _moduleMetaData;

  LocationMetaData(this._moduleMetaData);

  /// Clears all location meta data.
  void clearCache() {
    _sourceToTokenPosTable.clear();
    _scriptIdToLocation.clear();
    _sourceToLocation.clear();
    _processedModules.clear();
  }

  /// Returns all [Location] data for a provided Dart source.
  Future<Set<Location>> locationsForDart(String serverPath) async {
    var module = await _moduleMetaData.moduleForSource(serverPath);
    var cache = _sourceToLocation[serverPath];
    if (cache != null) return cache;

    for (var location in await _moduleMetaData.locationsForModule(module)) {
      noteLocation(location.dartLocation.uri.serverPath, location,
          location.jsLocation.scriptId);
    }

    return _sourceToLocation[serverPath] ?? {};
  }

  /// Returns all [Location] data for a provided JS scriptId.
  Future<Set<Location>> locationsForJs(String scriptId) async {
    var module = await _moduleMetaData.moduleForScriptId(scriptId);

    var cache = _scriptIdToLocation[scriptId];
    if (cache != null) return cache;

    for (var location in await _moduleMetaData.locationsForModule(module)) {
      noteLocation(location.dartLocation.uri.serverPath, location,
          location.jsLocation.scriptId);
    }

    return _scriptIdToLocation[scriptId] ?? {};
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
  Future<List<List<int>>> tokenPosTableFor(String serverPath) async {
    var tokenPosTable = _sourceToTokenPosTable[serverPath];
    if (tokenPosTable != null) return tokenPosTable;
    // Construct the tokenPosTable which is of the form:
    // [lineNumber, (tokenId, columnNumber)*]
    tokenPosTable = <List<int>>[];
    var locations = await locationsForDart(serverPath);
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
}
