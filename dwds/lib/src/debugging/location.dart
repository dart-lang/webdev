// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_maps/parser.dart';

import '../utilities/dart_uri.dart';

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
