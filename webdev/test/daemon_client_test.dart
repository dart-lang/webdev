// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build_daemon/client.dart';
import 'package:test/test.dart';
import 'package:webdev/src/daemon_client.dart';

void main() {
  group('startBuildDaemon', () {
    test('converts MissingPortFile into DaemonException', () async {
      await expectLater(
        startBuildDaemon(
          '.',
          const <String>[],
          connect: (_, _, _) =>
              Future.error(MissingPortFile('Timeout waiting for port file.')),
        ),
        throwsA(
          isA<DaemonException>()
              .having(
                (e) => e.message,
                'message',
                contains('Failed to connect to the build daemon'),
              )
              .having((e) => e.message, 'message', contains('MissingPortFile'))
              .having(
                (e) => e.message,
                'message',
                contains('.dart_tool/build_daemon'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('dart pub upgrade build_daemon'),
              ),
        ),
      );
    });

    test('converts OptionsSkew into DaemonException', () async {
      await expectLater(
        startBuildDaemon(
          '.',
          const <String>[],
          connect: (_, _, _) => Future.error(OptionsSkew()),
        ),
        throwsA(
          isA<DaemonException>().having(
            (e) => e.message,
            'message',
            contains('Incompatible options with current running build daemon'),
          ),
        ),
      );
    });

    test('converts VersionSkew into DaemonException', () async {
      await expectLater(
        startBuildDaemon(
          '.',
          const <String>[],
          connect: (_, _, _) => Future.error(VersionSkew()),
        ),
        throwsA(
          isA<DaemonException>().having(
            (e) => e.message,
            'message',
            contains('Incompatible build_daemon version detected'),
          ),
        ),
      );
    });
  });
}
