// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/debugging/modules.dart';
import 'package:test/test.dart';

void main() {
  group('noteModule', () {
    test('handles Google3 URLs', () async {
      var modules = Modules(null, '', null);
      await modules.noteModule('foo/google3/bar/blah.ddc.js', '10');
      expect(await modules.scriptIdForModule('bar/blah'), equals('10'));
    });

    test('ignores non-module paths', () async {
      var modules = Modules(null, '', null);
      await modules.noteModule('foo/bar', '10');
      expect(await modules.scriptIdForModule('foo/bar'), isNull);
    });

    test('rewrites third_party Google3 paths', () async {
      var modules = Modules(null, '', null);
      await modules.noteModule('/third_party/dart/test/lib/test.ddc.js', '10');
      expect(
          await modules.scriptIdForModule('packages/test/test'), equals('10'));
    });

    test('handles package paths', () async {
      var modules = Modules(null, '', null);
      await modules.noteModule('/packages/shelf/shelf.ddc.js', '10');
      expect(await modules.scriptIdForModule('packages/shelf/shelf'),
          equals('10'));
    });

    test('handles absolute paths', () async {
      var modules = Modules(null, '', null);
      await modules.noteModule('/foo/bar.ddc.js', '10');
      expect(await modules.scriptIdForModule('foo/bar'), equals('10'));
    });
  });
}
