// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';

import 'test_utils.dart';

void main() {
  group('should succeed with valid configuration', () {
    for (var withDDC in [true, false]) {
      test(withDDC ? 'DDC' : 'dart2js', () async {
        var exampleDirectory = p.absolute(p.join(p.current, '..', 'example'));
        var process = await TestProcess.start(pubPath, ['get'],
            workingDirectory: exampleDirectory,
            environment: _getPubEnvironment());

        await process.shouldExit(0);

        await d.file('.packages', isNotEmpty).validate(exampleDirectory);
        await d.file('pubspec.lock', isNotEmpty).validate(exampleDirectory);

        var args = ['build', '-o', 'web:${d.sandbox}'];
        if (withDDC) {
          args.add('--no-release');
        }

        process = await runWebDev(args, workingDirectory: exampleDirectory);

        var expectedItems = <Object>['[INFO] Succeeded'];
        if (!withDDC) {
          expectedItems.add(anyOf(
              contains('with 0 outputs'), contains('Running dart2js with')));
        }

        await checkProcessStdout(process, expectedItems);
        await process.shouldExit(0);

        await d.file('main.dart.js', isNotEmpty).validate();

        for (var ddcFile in ['main.dart.bootstrap.js', 'main.ddc.js']) {
          if (withDDC) {
            await d.file(ddcFile, isNotEmpty).validate();
          } else {
            await d.nothing(ddcFile).validate();
          }
        }
      }, timeout: const Timeout(const Duration(minutes: 5)));
    }
  });
}

/// Returns an environment map that includes `PUB_ENVIRONMENT`.
///
/// Maintains any existing values for this environment var.
/// Adds a new value that flags this is a bot/test and not human usage.
Map<String, String> _getPubEnvironment() {
  var pubEnvironmentKey = 'PUB_ENVIRONMENT';
  var pubEnvironment = Platform.environment[pubEnvironmentKey] ?? '';
  if (pubEnvironment.isNotEmpty) {
    pubEnvironment = '$pubEnvironment;';
  }
  pubEnvironment = '${pubEnvironment}bot.pkg.webdev.test';

  var environment = {'PUB_ENVIRONMENT': pubEnvironment};

  return environment;
}
