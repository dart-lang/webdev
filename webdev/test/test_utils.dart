// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:test_common/test_sdk_layout.dart';
import 'package:test_process/test_process.dart';

final _webdevBin = p.absolute(p.join('bin', 'webdev.dart'));

class TestRunner {
  late TestSdkConfigurationProvider sdkConfigurationProvider;
  late TestSdkLayout sdkLayout;

  Future<void> setUpAll({bool verbose = false}) async {
    // Generate missing SDK assets if needed.
    sdkConfigurationProvider = TestSdkConfigurationProvider(verbose: verbose);
    sdkLayout = sdkConfigurationProvider.sdkLayout;

    try {
      // Make sure configuration was created correctly.
      final configuration = await sdkConfigurationProvider.configuration;
      configuration.validate();
    } catch (_) {
      tearDownAll();
      rethrow;
    }
  }

  void tearDownAll() {
    sdkConfigurationProvider.dispose();
  }

  Future<TestProcess> runWebDev(List<String> args,
      {String? workingDirectory}) async {
    var fullArgs = [_webdevBin, ...args];

    return TestProcess.start(sdkLayout.dartPath, fullArgs,
        workingDirectory: workingDirectory);
  }

  Future<String> prepareWorkspace() async {
    var exampleDirectory =
        p.absolute(p.join(p.current, '..', 'fixtures', '_webdevSoundSmoke'));

    var process = await TestProcess.start(
        sdkLayout.dartPath, ['pub', 'upgrade'],
        workingDirectory: exampleDirectory, environment: getPubEnvironment());

    await process.shouldExit(0);
    return exampleDirectory;
  }
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
