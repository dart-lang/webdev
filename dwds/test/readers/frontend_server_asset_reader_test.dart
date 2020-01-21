// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  FrontendServerAssetReader assetReader;
  Directory tempFixtures;
  File jsonOriginal;
  File mapOriginal;

  Future<void> _createTempFixtures() async {
    var fixtures = p.join('test', 'fixtures');
    tempFixtures = await Directory.systemTemp.createTemp('dwds_test_fixtures');
    await tempFixtures.create();
    jsonOriginal = await File(p.join(fixtures, 'main.dart.dill.json'))
        .copy(p.join(tempFixtures.path, 'main.dart.dill.json'));
    mapOriginal = await File(p.join(fixtures, 'main.dart.dill.map'))
        .copy(p.join(tempFixtures.path, 'main.dart.dill.map'));
  }

  setUp(() async {
    await _createTempFixtures();
    assetReader =
        FrontendServerAssetReader(p.join(tempFixtures.path, 'main.dart.dill'));
    await assetReader.updateCaches();
  });

  tearDown(() async {
    if (await tempFixtures.exists()) await tempFixtures.delete(recursive: true);
  });

  group('FrontendServerAssetReader', () {
    group('source maps', () {
      test('can be read', () async {
        var result =
            await assetReader.sourceMapContents('web/main.dart.lib.js.map');
        expect(result, isNotNull);
      });

      test('are cached', () async {
        // Remove the underlying fixtures.
        await tempFixtures.delete(recursive: true);

        var cachedResult =
            await assetReader.sourceMapContents('web/main.dart.lib.js.map');
        expect(cachedResult, isNotNull);
      });

      test('are null if the path does not exist', () async {
        var result =
            await assetReader.sourceMapContents('web/foo.dart.lib.js.map');
        expect(result, isNull);
      });

      test('are updated with new incremental results', () async {
        var missingResult =
            await assetReader.sourceMapContents('web/foo.dart.lib.js.map');
        expect(missingResult, isNull);

        // Update fixture.
        await File(p.join(tempFixtures.path, 'main.dart.dill.incremental.json'))
            .writeAsString((await jsonOriginal.readAsString())
                .replaceAll('web/main.dart.lib.js', 'web/foo.dart.lib.js'));
        await File(p.join(tempFixtures.path, 'main.dart.dill.incremental.map'))
            .writeAsString((await mapOriginal.readAsString())
                .replaceAll('web/main.dart.lib.js', 'web/foo.dart.lib.js'));

        await assetReader.updateCaches();

        var newResult =
            await assetReader.sourceMapContents('web/foo.dart.lib.js.map');
        expect(newResult, isNotNull);
      });
    });
  });
}
