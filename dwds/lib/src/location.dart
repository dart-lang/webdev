// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

var _startTokenId = 1337;

/// A source location, with both Dart and JS information.
///
/// Note that line and column numbers here are always 1-based. The  Dart VM
/// Service protocol line/column numbers are one-based, but in JS source maps and
/// the Chrome protocol are zero-based, so they require translation.
class Location {
  final String jsScriptId;
  final int jsLine;
  final int jsColumn;
  final String dartUri;

  /// 1 based row offset within the source code.
  final int dartLine;

  /// 1 based column offset within the source code.
  final int dartColumn;

  /// An arbitrary integer value used to represent this location.
  final int tokenPos;

  Location(
    this.jsScriptId,
    this.jsLine,
    this.jsColumn,
    this.dartUri,
    this.dartLine,
    this.dartColumn,
  ) : tokenPos = _startTokenId++;
}
