// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// A source location, with both Dart and JS information.
///
/// Note that line and column numbers here are always 1-based. The  Dart VM
/// Service protocol line/column numbers are one-based, but in JS source maps and
/// the Chrome protocol are zero-based, so they require translation.
class Location {
  Location(this.jsScriptId, this.jsLine, this.jsColumn, this.dartUri,
      this.dartLine, this.dartColumn, this.dartTokenPos);

  final String jsScriptId;
  final int jsLine;
  final int jsColumn;
  final String dartUri;
  final int dartLine;
  final int dartColumn;
  final int dartTokenPos;
}
