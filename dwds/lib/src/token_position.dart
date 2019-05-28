// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

var _tokenId = 1337;

/// A location within source code.
///
/// See:
/// https://github.com/dart-lang/sdk/blob/master/runtime/vm/service/service.md#script
class TokenPos {
  /// 1 based row offset within the source code.
  final int line;

  /// 1 based column offset within the source code.
  final int column;

  /// An arbitrary integer value used to represent this location.
  final int id;

  TokenPos(this.line, this.column) : id = ++_tokenId;
}
