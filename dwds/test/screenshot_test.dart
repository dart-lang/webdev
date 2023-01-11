// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 2))

import 'package:test/test.dart';

import 'fixtures/context.dart';

final context = TestContext.withSoundNullSafety();

void main() {
  setUpAll(() async {
    await context.setUpAll();
    await context.setUp();
  });

  tearDownAll(() async {
    await context.tearDown();
    await context.tearDownAll();
  });

  test('can take screenshots', () async {
    final response = await context.debugConnection.vmService
        .callServiceExtension('ext.dwds.screenshot');
    expect(response.json!['data'], isNotNull);
  });
}
