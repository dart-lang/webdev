// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

void main() {
  late final TestSdkConfigurationProvider provider;

  setUp(() {
    provider = TestSdkConfigurationProvider();
  });

  tearDown(() {
    provider.dispose();
  });

  test('DWDS starts DDS with a specified port', () async {
    final context = TestContext(TestProject.test, provider);

    // Find a unused port for the test.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final expectedPort = server.port;
    await server.close();

    await context.setUp(
      debugSettings: TestDebugSettings.noDevTools().copyWith(
        ddsPort: expectedPort,
      ),
    );
    expect(Uri.parse(context.debugConnection.ddsUri!).port, expectedPort);
  });
}
