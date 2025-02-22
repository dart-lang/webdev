// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';

import 'package:webdev/src/logging.dart';
import 'package:webdev/src/serve/utils.dart';

import 'test_utils.dart';

void main() {
  group('serve app with TLS options', () {
    // Change to true for debugging.
    final debug = false;

    final testRunner = TestRunner();
    late String exampleDirectory;

    setUpAll(() async {
      configureLogWriter(debug);
      await testRunner.setUpAll();
      exampleDirectory = p.absolute(
          p.join(p.current, '..', 'fixtures', '_experimentSound'));

      final process = await TestProcess.start(
        'dart',
        ['pub', 'upgrade'],
        workingDirectory: exampleDirectory,
        environment: getPubEnvironment(),
      );

      await process.shouldExit(0);

      await d
          .file('.dart_tool/package_config.json', isNotEmpty)
          .validate(exampleDirectory);
      await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);
    });

    test('listens on a loopback interface', () async {
      final port = await findUnusedPort();
      final args = [
        'serve',
        'web:$port',
        '--hostname=0.0.0.0',
        '--tls-cert-chain=localhost+2.pem',
        '--tls-cert-key=localhost+2-key.pem',
      ];

      final process = await testRunner.runWebDev(args,
          workingDirectory: exampleDirectory);
      await expectLater(process.stdout, emitsThrough(contains('Succeeded')));

      final client = HttpClient()
        ..badCertificateCallback = (_, __, ___) => true;
      try {
        final request =
            await client.getUrl(Uri.parse('https://localhost:$port'));
        final response = await request.close();
        expect(response.statusCode, equals(200));
      } finally {
        client.close(force: true);
      }

      await process.kill();
      await process.shouldExit();
    });

    test('listens on a non-loopback interface', () async {
      final port = await findUnusedPort();
      final args = [
        'serve',
        'web:$port',
        '--hostname=0.0.0.0',
        '--tls-cert-chain=localhost+2.pem',
        '--tls-cert-key=localhost+2-key.pem',
      ];

      final process = await testRunner.runWebDev(args,
          workingDirectory: exampleDirectory);
      await expectLater(process.stdout, emitsThrough(contains('Succeeded')));

      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final nonLoopback = interfaces.expand((i) => i.addresses).firstOrNull;

      if (nonLoopback == null) {
        Logger.root.info(
            'No non-loopback IPv4 address available, skipping hostname test.');
      } else {
        final client = HttpClient()
          ..badCertificateCallback = (_, __, ___) => true;
        try {
          final request = await client
              .getUrl(Uri.parse('https://${nonLoopback.address}:$port'));
          final response = await request.close();
          expect(response.statusCode, equals(200));
        } finally {
          client.close(force: true);
        }
      }

      await process.kill();
      await process.shouldExit();
    });
  });
}
