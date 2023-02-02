// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(minutes: 1))
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:test/test.dart';

void main() {
  Process? _serveProcess;

  setUp(() async {
    await Process.run(
      'dart',
      ['pub', 'global', 'deactivate', 'webdev'],
    );
  });

  tearDown(() async {
    if (_serveProcess != null) {
      Process.killPid(_serveProcess!.pid);
      _serveProcess = null;
    }
  });

  test('can activate and serve webdev', () async {
    final activateProcess = await Process.run(
      'dart',
      ['pub', 'global', 'activate', 'webdev'],
    );
    final activateStdout = stringifyOutput(await activateProcess.stdout);
    expect(activateStdout, contains('Activated webdev'));
    final activateStderr = stringifyOutput(await activateProcess.stderr);
    expect(activateStderr, isEmpty);

    final soundPackage =
        p.absolute(p.join(p.current, '..', 'fixtures', '_webdevSoundSmoke'));

    _serveProcess = await Process.start(
      'webdev',
      ['serve'],
      workingDirectory: soundPackage,
    );

    await expectLater(
        _serveProcess!.stdout.transform(utf8.decoder),
        emitsThrough(
          contains('Serving `web` on'),
        ));
  });
}

String stringifyOutput(dynamic output) {
  if (output == null) return '';
  if (output == String) return output as String;
  final outputList = output is List ? output : [output];
  return outputList.map((output) => '$output').join('\n');
}
