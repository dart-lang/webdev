// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))

import 'package:dwds/src/readers/proxy_server_asset_reader.dart';
import 'package:test/test.dart';

import '../fixtures/context.dart';
import '../utils/version_compatibility.dart';

void main() {
  group('ProxyServerAssetReader', () {
    final context = TestContext(nullSafety: NullSafety.weak);
    late ProxyServerAssetReader assetReader;
    setUpAll(() async {
      await context.setUp();
      assetReader = context.testServer.assetReader as ProxyServerAssetReader;
    });
    test('returns null if the dart path does not exist', () async {
      final result = await assetReader.dartSourceContents('some/path/foo.dart');
      expect(result, isNull);
    });

    test('can read dart sources', () async {
      final result =
          await assetReader.dartSourceContents('hello_world/main.dart');
      expect(result, isNotNull);
    });

    test('can read source maps', () async {
      final result = await assetReader
          .dartSourceContents('hello_world/main.unsound.ddc.js.map');
      expect(result, isNotNull);
    });

    test('returns null if the source map path does not exist', () async {
      final result = await assetReader
          .dartSourceContents('hello_world/foo.unsound.ddc.js.map');
      expect(result, isNull);
    });
  },
      // TODO(https://github.com/dart-lang/webdev/issues/1818) Re-enable.
      skip: !supportedMode(
          compilationMode: CompilationMode.frontendServer,
          nullSafetyMode: NullSafety.weak));
}
