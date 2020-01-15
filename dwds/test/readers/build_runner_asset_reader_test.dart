// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/dwds.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';

void main() {
  final context = TestContext();
  BuildRunnerAssetReader assetReader;
  setUpAll(() async {
    await context.setUp(useBuildDaemon: true);
    assetReader = context.testServer.assetReader as BuildRunnerAssetReader;
  });

  group('BuildRunnerAssetHandler', () {
    test('returns null if the dart path does not exist', () async {
      var result = await assetReader.dartSourceContents('some/path/foo.dart');
      expect(result, isNull);
    });

    test('can read dart sources', () async {
      var result =
          await assetReader.dartSourceContents('hello_world/main.dart');
      expect(result, isNotNull);
    });

    test('can read source maps', () async {
      var result =
          await assetReader.dartSourceContents('hello_world/main.ddc.js.map');
      expect(result, isNotNull);
    });

    test('returns null if the source map path does not exist', () async {
      var result =
          await assetReader.dartSourceContents('hello_world/foo.ddc.js.map');
      expect(result, isNull);
    });
  });
}
