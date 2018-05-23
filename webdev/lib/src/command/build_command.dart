// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:args/command_runner.dart';

import 'command_base.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends CommandBase {
  BuildCommand() : super(releaseDefault: true, outputDefault: 'web:build');

  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  @override
  Future<int> run() {
    if (argResults.rest.isNotEmpty) {
      throw new UsageException(
          'Arguments were provided that are not supported: '
          '"${argResults.rest.join(' ')}".',
          argParser.usage);
    }
    return runCore('build', extraArgs: ['--fail-on-severe']);
  }
}
