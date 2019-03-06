// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';
import 'package:webdev/src/util.dart';

final _webdevBin = p.absolute(p.join('bin', 'webdev.dart'));

Future<TestProcess> runWebDev(List<String> args, {String workingDirectory}) {
  var fullArgs = [_webdevBin]..addAll(args);

  return TestProcess.start(dartPath, fullArgs,
      workingDirectory: workingDirectory);
}

Future checkProcessStdout(TestProcess process, List items) async {
  for (var item in items) {
    if (item is! Matcher) {
      item = contains(item);
    }

    await expectLater(process.stdout, emitsThrough(item));
  }
}

/// Returns an environment map that includes `PUB_ENVIRONMENT`.
///
/// Maintains any existing values for this environment var.
/// Adds a new value that flags this is a bot/test and not human usage.
Map<String, String> getPubEnvironment() {
  var pubEnvironmentKey = 'PUB_ENVIRONMENT';
  var pubEnvironment = Platform.environment[pubEnvironmentKey] ?? '';
  if (pubEnvironment.isNotEmpty) {
    pubEnvironment = '$pubEnvironment;';
  }
  pubEnvironment = '${pubEnvironment}bot.pkg.webdev.test';

  var environment = {'PUB_ENVIRONMENT': pubEnvironment};

  return environment;
}
