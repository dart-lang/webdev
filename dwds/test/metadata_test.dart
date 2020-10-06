// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dwds/dwds.dart';
import 'package:test/test.dart';

class FakeAssetReader implements AssetReader {
  @override
  Future<String> dartSourceContents(String serverPath) =>
      throw UnimplementedError();

  @override
  Future<String> metadataContents(String serverPath) async =>
      '{"version":"1.0.0","name":"web/main","closureName":"load__web__main",'
      '"sourceMapUri":"foo/web/main.ddc.js.map",'
      '"moduleUri":"foo/web/main.ddc.js",'
      '"libraries":[{"name":"main",'
      '"importUri":"org-dartlang-app:///web/main.dart",'
      '"fileUri":"org-dartlang-app:///web/main.dart","partUris":[]}]}\n'
      '// intentionally empty: package blah has no dart sources';

  @override
  Future<String> sourceMapContents(String serverPath) =>
      throw UnimplementedError();

  @override
  Future<void> close() async {}
}

void main() {
  test('can parse metadata with empty sources', () async {
    var provider = MetadataProvider(
        FakeAssetReader(), null, (level, message) => printOnFailure(message));
    await provider.initialize('foo.bootstrap.js');
    expect(await provider.libraries,
        contains('org-dartlang-app:///web/main.dart'));
  });
}
