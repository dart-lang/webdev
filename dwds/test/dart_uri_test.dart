// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.9

@TestOn('vm')
import 'dart:io';

import 'package:dwds/src/loaders/strategy.dart';
import 'package:dwds/src/utilities/dart_uri.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures/fakes.dart';

class TestStrategy extends FakeStrategy {
  @override
  String serverPathForAppUri(String appUri) {
    if (appUri.startsWith('org-dartlang-app:')) return 'foo';
    return null;
  }
}

void main() {
  globalLoadStrategy = TestStrategy();
  group('DartUri', () {
    test('parses package : paths', () {
      var uri = DartUri('package:path/path.dart');
      expect(uri.serverPath, 'packages/path/path.dart');
    });

    test('parses package : paths with root', () {
      var uri = DartUri(
          'package:path/path.dart', 'http://localhost:8080/foo/bar/blah');
      expect(uri.serverPath, 'foo/bar/packages/path/path.dart');
    });

    test('parses org-dartlang-app paths', () {
      var uri = DartUri('org-dartlang-app:////blah/main.dart');
      expect(uri.serverPath, 'foo');
    });

    test('parses packages paths', () {
      var uri = DartUri('/packages/blah/foo.dart');
      expect(uri.serverPath, 'packages/blah/foo.dart');
    });

    test('parses http paths', () {
      var uri = DartUri('http://localhost:8080/web/main.dart');
      expect(uri.serverPath, 'web/main.dart');
    });

    group('initialized with current SDK directory', () {
      setUpAll(() async {
        await DartUri.initialize();
        await DartUri.recordAbsoluteUris(['dart:io', 'dart:html']);
      });

      tearDownAll(DartUri.clear);

      test('can resolve uris', () {
        var resolved = DartUri.toResolvedUri('dart:io');
        expect(resolved, 'org-dartlang-sdk:///sdk/lib/io/io.dart');
      });

      test('can unresolve uris', () {
        var unresolved =
            DartUri.toPackageUri('org-dartlang-sdk:///sdk/lib/io/io.dart');
        expect(unresolved, 'dart:io');
      });
    });

    group('initialized with other SDK directory', () {
      Directory outputDir;

      setUpAll(() async {
        var systemTempDir = Directory.systemTemp;
        outputDir = systemTempDir.createTempSync('foo bar');

        var sdkDir = p.dirname(p.dirname(Platform.resolvedExecutable));
        var librariesPath = p.join(sdkDir, 'lib', 'libraries.json');

        // copy libraries.json to a new location mimicking SDK directory structure.
        var fakeSdkDir = outputDir.path;
        var fakeLibrariesDir = p.join(fakeSdkDir, 'lib');
        var fakeLibrariesPath = p.join(fakeLibrariesDir, 'libraries.json');

        Directory(fakeLibrariesDir).createSync();
        File(librariesPath).copySync(fakeLibrariesPath);

        await DartUri.initialize(sdkDir: Uri.parse(fakeSdkDir));
        await DartUri.recordAbsoluteUris(['dart:io', 'dart:html']);
      });

      tearDownAll(() async {
        DartUri.clear();
        await outputDir?.delete(recursive: true);
      });

      test('can resolve uris', () {
        var resolved = DartUri.toResolvedUri('dart:io');
        expect(resolved, 'org-dartlang-sdk:///sdk/lib/io/io.dart');
      });

      test('can unresolve uris', () {
        var unresolved =
            DartUri.toPackageUri('org-dartlang-sdk:///sdk/lib/io/io.dart');
        expect(unresolved, 'dart:io');
      });
    });
  });
}
