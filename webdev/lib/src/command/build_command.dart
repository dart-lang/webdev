// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'build_runner_command_base.dart';

/// Command to execute pub run build_runner build.
class BuildCommand extends BuildRunnerCommandBase {
  @override
  final name = 'build';

  @override
  final description = 'Run builders to build a package.';

  @override
  Future run() => runCore('build');
}
