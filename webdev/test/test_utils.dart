// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:dwds/expression_compiler.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_common/test_sdk_configuration.dart';
import 'package:test_common/test_sdk_layout.dart';
import 'package:test_process/test_process.dart';

final _webdevBin = p.absolute(p.join('bin', 'webdev.dart'));

class TestRunner {
  late TestSdkConfigurationProvider sdkConfigurationProvider;
  late TestSdkLayout sdkLayout;
  final bool canaryFeatures;
  final ModuleFormat ddcModuleFormat;

  TestRunner({
    this.canaryFeatures = false,
    this.ddcModuleFormat = ModuleFormat.amd,
  });

  Future<void> setUpAll({bool verbose = false}) async {
    // Generate missing SDK assets if needed.
    sdkConfigurationProvider = TestSdkConfigurationProvider(
      verbose: verbose,
      canaryFeatures: canaryFeatures,
      ddcModuleFormat: ddcModuleFormat,
    );
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

  Future<TestProcess> runWebDev(
    List<String> args, {
    String? workingDirectory,
  }) async {
    final fullArgs = [_webdevBin, ...args];
    if (canaryFeatures) {
      fullArgs.add('--canary');
    }

    if (ddcModuleFormat == ModuleFormat.ddc) {
      fullArgs.addAll(['--module-format', 'ddc']);
    }

    return TestProcess.start(
      sdkLayout.dartPath,
      fullArgs,
      workingDirectory: workingDirectory,
    );
  }

  /// Copies [source] to [destination], skipping '.dart_tool' to ignore built
  /// output from previous runs.
  void _copyCleanDirectory(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      if (entity is Directory) {
        if (p.basename(entity.path) == '.dart_tool') continue;
        final newDirectory = Directory(
          p.join(destination.absolute.path, p.basename(entity.path)),
        );
        newDirectory.createSync(recursive: true);
        _copyCleanDirectory(entity.absolute, newDirectory);
      } else if (entity is File) {
        entity.copySync(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  Future<String> prepareWorkspace() async {
    final originalDirectory = p.absolute(
      p.join(p.current, '..', 'fixtures', '_webdev_smoke'),
    );
    final tempDir = Directory.systemTemp.createTempSync('webdev_smoke_');
    final exampleDirectory = tempDir.path;
    _copyCleanDirectory(Directory(originalDirectory), tempDir);

    final process = await TestProcess.start(
      sdkLayout.dartPath,
      ['pub', 'upgrade'],
      workingDirectory: exampleDirectory,
      environment: getPubEnvironment(),
    );

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
  final pubEnvironmentKey = 'PUB_ENVIRONMENT';
  var pubEnvironment = Platform.environment[pubEnvironmentKey] ?? '';
  if (pubEnvironment.isNotEmpty) {
    pubEnvironment = '$pubEnvironment;';
  }
  pubEnvironment = '${pubEnvironment}bot.pkg.webdev.test';

  final environment = {'PUB_ENVIRONMENT': pubEnvironment};

  return environment;
}
