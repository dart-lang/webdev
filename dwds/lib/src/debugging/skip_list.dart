// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

import 'location.dart';

const maxValue = 2147483647;

class SkipLists {
  // Map of script ID to scriptList.
  final _idToList = <String, List<Map<String, dynamic>>>{};

  void initialize() => _idToList.clear();

  /// Returns a skipList as defined by the Chrome DevTools Protocol.
  ///
  /// A `skipList` is an array of `LocationRange`s see:
  /// https://chromedevtools.github.io/devtools-protocol/tot/Debugger/#method-stepInto
  ///
  /// Can return a cached value.
  Future<List<Map<String, dynamic>>> compute(
    String scriptId,
    Set<Location> locations,
  ) async {
    if (_idToList.containsKey(scriptId)) return _idToList[scriptId];

    var ranges = <Map<String, dynamic>>[];
    var startLine = 0;
    var startColumn = 0;
    for (var location in locations) {
      // Account for 1 based.
      var endLine = location.jsLocation.line - 1;
      var endColumn = location.jsLocation.column - 1;
      // Stop before the known location.
      endColumn -= 1;
      if (endColumn < 0) {
        endLine -= 1;
        endColumn = maxValue;
      }
      if (endLine > startLine || endColumn > startColumn) {
        ranges.add(
            _rangeFor(scriptId, startLine, startColumn, endLine, endColumn));
        startLine = location.jsLocation.line - 1;
        startColumn = location.jsLocation.column;
      }
    }
    ranges.add(_rangeFor(scriptId, startLine, startColumn, maxValue, maxValue));

    _idToList[scriptId] = ranges;
    return ranges;
  }

  Map<String, dynamic> _rangeFor(
    String scriptId,
    int startLine,
    int startColumn,
    int endLine,
    int endColumn,
  ) =>
      {
        'scriptId': scriptId,
        'start': {'lineNumber': startLine, 'columnNumber': startColumn},
        'end': {'lineNumber': endLine, 'columnNumber': endColumn}
      };
}
