// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:path/path.dart' as p;
import 'package:source_maps/parser.dart';
import 'package:source_maps/source_maps.dart';

import '../loaders/strategy.dart';
import '../readers/asset_reader.dart';
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
    String module,
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
    return Location._(
      JsLocation.fromZeroBased(module, jsLine, jsColumn),
      DartLocation.fromZeroBased(dartUri, dartLine, dartColumn),
    );
  }

  @override
  String toString() => '$dartLocation -> $jsLocation';
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

  @override
  String toString() => '[${uri.serverPath}:$line:$column]';

  static DartLocation fromZeroBased(DartUri uri, int line, int column) =>
      DartLocation._(uri, line + 1, column + 1);

  static DartLocation fromOneBased(DartUri uri, int line, int column) =>
      DartLocation._(uri, line, column);
}

/// Location information for a JS source.
class JsLocation {
  final String module;

  /// 1 based row offset within the JS source code.
  final int line;

  /// 1 based column offset within the JS source code.
  final int column;

  JsLocation._(
    this.module,
    this.line,
    this.column,
  );

  @override
  String toString() => '[$module:$line:$column]';

  static JsLocation fromZeroBased(String module, int line, int column) =>
      JsLocation._(module, line + 1, column + 1);

  static JsLocation fromOneBased(String module, int line, int column) =>
      JsLocation._(module, line, column);
}

/// Contains meta data for known [Location]s.
class Locations {
  /// Map from Dart server path to all corresponding [Location] data.
  final _sourceToLocation = <String, Set<Location>>{};

  /// Map from Dart server path to tokenPosTable as defined in the
  /// Dart VM Service Protocol:
  /// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
  final _sourceToTokenPosTable = <String, List<List<int>>>{};

  /// The set of all known [Location]s for a module.
  final _moduleToLocations = <String, Set<Location>>{};

  /// Set of all modules for which the corresponding source map has been
  /// processed.
  final _processedModules = <String>{};

  final AssetReader _assetReader;
  final Modules _modules;
  final String _root;

  Locations(this._assetReader, this._modules, this._root);

  Modules get modules => _modules;

  /// Clears all location meta data.
  void clearCache() {
    _sourceToTokenPosTable.clear();
    _sourceToLocation.clear();
    _moduleToLocations.clear();
    _processedModules.clear();
  }

  /// Returns all [Location] data for a provided Dart source.
  Future<Set<Location>> locationsForDart(String serverPath) async {
    var module = await _modules.moduleForSource(serverPath);
    var cache = _sourceToLocation[serverPath];
    if (cache != null) return cache;
    await _locationsForModule(module);
    return _sourceToLocation[serverPath] ?? {};
  }

  /// Returns all [Location] data for a provided JS server path.
  Future<Set<Location>> locationsForUrl(String url) async {
    var module = globalLoadStrategy.moduleForServerPath(Uri.parse(url).path);
    var cache = _moduleToLocations[module];
    if (cache != null) return cache;
    return await _locationsForModule(module) ?? {};
  }

  /// Find the [Location] for the given Dart source position.
  ///
  /// The [line] number is 1-based.
  Future<Location> locationForDart(DartUri uri, int line) async =>
      (await locationsForDart(uri.serverPath)).firstWhere(
          (location) => location.dartLocation.line == line,
          orElse: () => null);

  /// Find the [Location] for the given JS source position.
  ///
  /// The [line] number is 1-based.
  Future<Location> locationForJs(String url, int line) async =>
      (await locationsForUrl(url)).firstWhere(
          (location) => location.jsLocation.line == line,
          orElse: () => null);

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
          .putIfAbsent(location.dartLocation.line, () => <Location>{})
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

  /// Returns all known [Location]s for the provided [module].
  ///
  /// [module] refers to the JS path of a DDC module without the extension.
  ///
  /// This will populate the [_sourceToLocation] and [_moduleToLocations] maps.
  Future<Set<Location>> _locationsForModule(String module) async {
    if (module == null) return {};
    if (_moduleToLocations[module] != null) return _moduleToLocations[module];
    var result = <Location>{};
    if (module?.isEmpty ?? true) return _moduleToLocations[module] = result;
    if (module.endsWith('dart_sdk')) {
      return result;
    }
    var modulePath = globalLoadStrategy.serverPathForModule(module);
    var sourceMapContents =
        await _assetReader.sourceMapContents('$modulePath.map');
    var scriptLocation = p.url.dirname('/$modulePath');
    if (sourceMapContents == null) return result;
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
          var path = p.url
              .normalize(p.url.joinAll([scriptLocation, ...relativeSegments]));
          var dartUri = DartUri(path, _root);
          result.add(Location.from(
            modulePath,
            lineEntry,
            entry,
            dartUri,
          ));
        }
      }
    }
    for (var location in result) {
      _sourceToLocation
          .putIfAbsent(location.dartLocation.uri.serverPath, () => <Location>{})
          .add(location);
    }
    return _moduleToLocations[module] = result;
  }
}
