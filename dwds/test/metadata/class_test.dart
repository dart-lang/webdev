// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))

import 'package:dwds/src/debugging/metadata/class.dart';
import 'package:test/test.dart';

void main() {
  test('Gracefully handles invalid length objects', () async {
    var metadata = ClassMetaData(length: null, classRef: classRefForUnknown);
    expect(metadata.length, isNull);

    metadata = ClassMetaData(length: {}, classRef: classRefForUnknown);
    expect(metadata.length, isNull);

    metadata = ClassMetaData(length: '{}', classRef: classRefForUnknown);
    expect(metadata.length, isNull);

    metadata = ClassMetaData(length: 0, classRef: classRefForUnknown);
    expect(metadata.length, equals(0));
  });
}
