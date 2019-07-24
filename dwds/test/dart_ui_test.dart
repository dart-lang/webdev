// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:test/test.dart';

void main() {
  group('DartUri', () {
    test('normalizes server paths', () {
      var uri = DartUri('../foo.dart', '/packages/blah/src/blah.dart');
      expect(uri.serverPath, 'packages/blah/foo.dart');
    });

    test('parses package : paths', () {
      var uri = DartUri('package:path/path.dart');
      expect(uri.serverPath, 'packages/path/path.dart');
    });

    test('parses org-dartlang-app paths', () {
      var uri = DartUri('org-dartlang-app:////web/main.dart');
      expect(uri.serverPath, 'web/main.dart');
    });

    test('parses packages paths', () {
      var uri = DartUri('/packages/blah/foo.dart');
      expect(uri.serverPath, 'packages/blah/foo.dart');
    });

    test('parses http paths', () {
      var uri = DartUri('http://localhost:8080/web/main.dart');
      expect(uri.serverPath, 'web/main.dart');
    });
  });
}
