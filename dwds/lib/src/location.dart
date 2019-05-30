// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:source_maps/parser.dart';

var _startTokenId = 1337;

/// A source location, with both Dart and JS information.
///
/// Note that line and column numbers here are always 1-based. The  Dart VM
/// Service protocol line/column numbers are one-based, but in JS source maps and
/// the Chrome protocol are zero-based, so they require translation.
class Location {
  final String jsScriptId;

  /// 1 based row offset within the JS source code.
  final int jsLine;

  /// 1 based column offset within the JS source code.
  final int jsColumn;

  final String dartUri;

  /// 1 based row offset within the Dart source code.
  final int dartLine;

  /// 1 based column offset within the Dart source code.
  final int dartColumn;

  /// An arbitrary integer value used to represent this location.
  final int tokenPos;

  Location._(
    this.jsScriptId,
    this.jsLine,
    this.jsColumn,
    this.dartUri,
    this.dartLine,
    this.dartColumn,
  ) : tokenPos = _startTokenId++;

  static Location from(
    String scriptId,
    TargetLineEntry lineEntry,
    TargetEntry entry,
    String dartUrl,
  ) {
    var dartLine = entry.sourceLine;
    var dartColumn = entry.sourceColumn;
    var jsLine = lineEntry.line;
    var jsColumn = entry.column;
    return Location._(
        scriptId, jsLine + 1, jsColumn + 1, dartUrl, dartLine, dartColumn);
  }
}
