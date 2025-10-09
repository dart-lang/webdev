// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('vm')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';

import 'fixtures/context.dart';
import 'fixtures/project.dart';
import 'fixtures/utilities.dart';

void main() {
  late TestSdkConfigurationProvider provider;
  late TestContext context;

  setUp(() {
    provider = TestSdkConfigurationProvider();
    context = TestContext(TestProject.test, provider);
  });

  tearDown(() async {
    await context.tearDown();
    provider.dispose();
  });

  test('DWDS starts DDS with a specified port (deprecated)', () async {
    // Find a unused port for the test.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final expectedPort = server.port;
    await server.close();

    await context.setUp(
      debugSettings: TestDebugSettings.noDevToolsLaunch().copyWith(
        ddsPort: expectedPort,
      ),
    );
    expect(Uri.parse(context.debugConnection.ddsUri!).port, expectedPort);
    expect(context.debugConnection.dtdUri, isNotNull);
  });

  test('DWDS starts DDS with a specified port', () async {
    // Find a unused port for the test.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final expectedPort = server.port;
    await server.close();

    await context.setUp(
      debugSettings: TestDebugSettings.noDevToolsLaunch().copyWith(
        ddsConfiguration: DartDevelopmentServiceConfiguration(
          port: expectedPort,
        ),
      ),
    );
    expect(Uri.parse(context.debugConnection.ddsUri!).port, expectedPort);
    expect(context.debugConnection.dtdUri, isNotNull);
  });
}
